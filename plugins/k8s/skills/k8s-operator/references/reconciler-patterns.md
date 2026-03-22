# Reconciler Patterns Reference

## Table of Contents
1. [Error Handling & Retry](#errors)
2. [Finalizers](#finalizers)
3. [Event Recording](#events)
4. [Owned Resource Management](#owned)
5. [Watching External Resources](#watches)
6. [Rate Limiting & Backoff](#ratelimiting)
7. [Metrics](#metrics)

---

## 1. Error Handling & Retry {#errors}

### Return patterns
```go
// Requeue immediately (rate-limited by workqueue)
return ctrl.Result{}, fmt.Errorf("transient error: %w", err)

// Requeue after fixed duration (for polling external systems)
return ctrl.Result{RequeueAfter: 30 * time.Second}, nil

// Done — rely on watches for next trigger
return ctrl.Result{}, nil

// Done with explicit requeue (rare — prefer watches)
return ctrl.Result{Requeue: true}, nil
```

### Conflict handling (optimistic locking)
```go
func (r *MyAppReconciler) updateWithRetry(ctx context.Context, obj *appsv1alpha1.MyApp) error {
    return retry.RetryOnConflict(retry.DefaultRetry, func() error {
        latest := &appsv1alpha1.MyApp{}
        if err := r.Get(ctx, client.ObjectKeyFromObject(obj), latest); err != nil {
            return err
        }
        latest.Status = obj.Status
        return r.Status().Update(ctx, latest)
    })
}
```

### Wrapping errors with context
```go
import "fmt"

if err := r.reconcileDeployment(ctx, myApp); err != nil {
    return ctrl.Result{}, fmt.Errorf("reconciling Deployment for %s: %w", myApp.Name, err)
}
```

### Transient vs permanent errors
```go
// Use a permanent error to stop requeuing (e.g., invalid config that won't self-heal)
import "sigs.k8s.io/controller-runtime/pkg/reconcile"

return ctrl.Result{}, reconcile.TerminalError(
    fmt.Errorf("invalid spec: image %q does not exist", myApp.Spec.Image),
)
```

---

## 2. Finalizers {#finalizers}

Finalizers let you run cleanup before the object is garbage-collected.

```go
const myFinalizer = "apps.example.com/finalizer"

func (r *MyAppReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    var obj appsv1alpha1.MyApp
    if err := r.Get(ctx, req.NamespacedName, &obj); err != nil {
        return ctrl.Result{}, client.IgnoreNotFound(err)
    }

    // Handle deletion
    if !obj.DeletionTimestamp.IsZero() {
        return r.handleDeletion(ctx, &obj)
    }

    // Ensure finalizer is registered
    if !controllerutil.ContainsFinalizer(&obj, myFinalizer) {
        controllerutil.AddFinalizer(&obj, myFinalizer)
        if err := r.Update(ctx, &obj); err != nil {
            return ctrl.Result{}, err
        }
        return ctrl.Result{}, nil // requeue after Update triggers watch
    }

    // ... normal reconcile
    return ctrl.Result{}, nil
}

func (r *MyAppReconciler) handleDeletion(ctx context.Context, obj *appsv1alpha1.MyApp) (ctrl.Result, error) {
    if !controllerutil.ContainsFinalizer(obj, myFinalizer) {
        return ctrl.Result{}, nil
    }

    // Run external cleanup (e.g., delete cloud resources)
    if err := r.cleanupExternalResources(ctx, obj); err != nil {
        return ctrl.Result{}, fmt.Errorf("cleanup failed: %w", err)
    }

    // Remove finalizer — object will now be deleted by GC
    controllerutil.RemoveFinalizer(obj, myFinalizer)
    return ctrl.Result{}, r.Update(ctx, obj)
}
```

**Rules:**
- Always add finalizer before creating external resources
- Never block deletion indefinitely — add a timeout or force-remove on repeated failures
- Use a single finalizer per controller; avoid multiple finalizers on the same object from the same controller

---

## 3. Event Recording {#events}

```go
// In reconciler struct
Recorder record.EventRecorder

// In SetupWithManager
r.Recorder = mgr.GetEventRecorderFor("myapp-controller")

// Usage: Normal, Warning
r.Recorder.Event(&myApp, corev1.EventTypeNormal, "Reconciled", "Successfully reconciled")
r.Recorder.Eventf(&myApp, corev1.EventTypeWarning, "DeploymentFailed",
    "Failed to reconcile Deployment: %v", err)
```

Use `Warning` for actionable problems; `Normal` for lifecycle milestones. Avoid high-frequency events (they flood the event log).

---

## 4. Owned Resource Management {#owned}

### CreateOrUpdate pattern
```go
func (r *MyAppReconciler) reconcileDeployment(ctx context.Context, myApp *appsv1alpha1.MyApp) error {
    deploy := &appsv1.Deployment{
        ObjectMeta: metav1.ObjectMeta{
            Name:      myApp.Name,
            Namespace: myApp.Namespace,
        },
    }

    _, err := controllerutil.CreateOrUpdate(ctx, r.Client, deploy, func() error {
        // Set owner reference
        if err := controllerutil.SetControllerReference(myApp, deploy, r.Scheme); err != nil {
            return err
        }
        // Mutate desired state
        deploy.Spec = buildDeploymentSpec(myApp)
        return nil
    })
    return err
}
```

### Server-Side Apply (preferred for complex resources)
```go
func (r *MyAppReconciler) applyDeployment(ctx context.Context, myApp *appsv1alpha1.MyApp) error {
    deploy := buildDeployment(myApp) // build full desired object

    return r.Patch(ctx, deploy, client.Apply,
        client.FieldOwner("myapp-controller"),
        client.ForceOwnership,
    )
}
```

SSA avoids last-write-wins conflicts and is preferred when multiple controllers might touch the same object.

---

## 5. Watching External Resources {#watches}

### Map function (unowned resource → owner enqueue)
```go
func (r *MyAppReconciler) findAppsForConfigMap(ctx context.Context, obj client.Object) []reconcile.Request {
    var appList appsv1alpha1.MyAppList
    if err := r.List(ctx, &appList,
        client.InNamespace(obj.GetNamespace()),
        client.MatchingLabels{"config-ref": obj.GetName()},
    ); err != nil {
        return nil
    }

    requests := make([]reconcile.Request, len(appList.Items))
    for i, app := range appList.Items {
        requests[i] = reconcile.Request{
            NamespacedName: types.NamespacedName{
                Name:      app.Name,
                Namespace: app.Namespace,
            },
        }
    }
    return requests
}
```

### Predicates to filter noise
```go
import "sigs.k8s.io/controller-runtime/pkg/predicate"

// Only trigger on spec changes (ignore status/metadata updates)
p := predicate.GenerationChangedPredicate{}

// Only trigger when labels change
p = predicate.LabelChangedPredicate{}

// Combine predicates
p = predicate.Or(
    predicate.GenerationChangedPredicate{},
    predicate.LabelChangedPredicate{},
)
```

---

## 6. Rate Limiting & Backoff {#ratelimiting}

Controller-runtime uses `workqueue.RateLimiter`. Default is exponential backoff (base 5ms, max 1000s).

### Custom rate limiter
```go
import (
    "k8s.io/client-go/util/workqueue"
    "sigs.k8s.io/controller-runtime/pkg/controller"
)

ctrl.NewControllerManagedBy(mgr).
    For(&appsv1alpha1.MyApp{}).
    WithOptions(controller.Options{
        RateLimiter: workqueue.NewItemExponentialFailureRateLimiter(
            5*time.Millisecond,  // base delay
            5*time.Minute,       // max delay
        ),
        MaxConcurrentReconciles: 5,
    }).
    Complete(r)
```

### Per-item rate limiting
Use `ctrl.Result{RequeueAfter: duration}` to implement polling without consuming error retries.

---

## 7. Metrics {#metrics}

Controller-runtime exposes Prometheus metrics automatically at `:8080/metrics`:
- `controller_runtime_reconcile_total{controller, result}` — reconcile count
- `controller_runtime_reconcile_errors_total{controller}` — error count
- `controller_runtime_reconcile_time_seconds{controller}` — latency histogram

### Custom metrics
```go
import "sigs.k8s.io/controller-runtime/pkg/metrics"
import "github.com/prometheus/client_golang/prometheus"

var (
    myAppGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
        Name: "myapp_replicas",
        Help: "Current replica count per MyApp",
    }, []string{"namespace", "name"})
)

func init() {
    metrics.Registry.MustRegister(myAppGauge)
}

// In reconciler
myAppGauge.WithLabelValues(myApp.Namespace, myApp.Name).Set(float64(myApp.Status.ReadyReplicas))
```
