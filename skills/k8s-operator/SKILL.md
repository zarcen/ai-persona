---
name: k8s-operator
description: >
  Expert guide for building Kubernetes operators with kubebuilder and controller-runtime.
  Covers CRD schema design, reconciler patterns, client-go usage, RBAC markers, webhooks,
  and envtest-based testing. Use when writing or reviewing Go code for Kubernetes operators.
version: 1.0.1
homepage: https://github.com/zarcen/ai-persona/tree/main/skills/k8s-operator
parameters:
  go_version: "1.25"
  controller_runtime_version: "v0.18"
  kubebuilder_version: "v4"
  k8s_version: "1.35"
  default_image_registry: "gcr.io/my-project"
  enable_webhooks: true
  enable_leader_election: true
  reconcile_timeout: "10m"
  requeue_after_error: "30s"
  max_concurrent_reconciles: 1
---

# Kubernetes Operator Skill (kubebuilder)

You are an expert Kubernetes operator developer. Follow these guidelines when writing,
reviewing, or scaffolding operator code using kubebuilder + controller-runtime + client-go.

## Parameters

Override defaults in `.claude/skill-params.yaml` or `.cursor/skill-params.yaml`:

```yaml
# skill-params.yaml
k8s_operator:
  go_version: "1.25"
  controller_runtime_version: "v0.18"
  kubebuilder_version: "v4"
  k8s_version: "1.35"
  default_image_registry: "gcr.io/my-project"
  enable_webhooks: true
  enable_leader_election: true
  reconcile_timeout: "10m"
  requeue_after_error: "30s"
  max_concurrent_reconciles: 1
```

---

## 1. Project Scaffolding

Always scaffold with kubebuilder v4:

```bash
# Initialize project
kubebuilder init \
  --domain example.com \
  --repo github.com/org/my-operator \
  --plugins go/v4

# Create API + controller
kubebuilder create api \
  --group apps \
  --version v1alpha1 \
  --kind MyApp \
  --resource \
  --controller

# Create webhook (if enable_webhooks=true)
kubebuilder create webhook \
  --group apps \
  --version v1alpha1 \
  --kind MyApp \
  --defaulting \
  --validation
```

**Directory layout after scaffolding:**
```
├── api/v1alpha1/
│   ├── myapp_types.go        # CRD types
│   ├── myapp_webhook.go      # Webhook logic
│   └── groupversion_info.go
├── internal/controller/
│   ├── myapp_controller.go   # Reconciler
│   └── myapp_controller_test.go
├── config/
│   ├── crd/                  # Generated CRD manifests
│   ├── rbac/                 # Generated RBAC
│   └── manager/              # Manager deployment
└── cmd/main.go
```

---

## 2. CRD Design

Read `references/crd-design.md` for full patterns. Key rules:

### Struct tags and markers
```go
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=`.status.phase`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`
type MyApp struct {
    metav1.TypeMeta   `json:",inline"`
    metav1.ObjectMeta `json:"metadata,omitempty"`
    Spec   MyAppSpec   `json:"spec,omitempty"`
    Status MyAppStatus `json:"status,omitempty"`
}
```

### Spec design rules
- All user-facing config goes in `Spec`; never put mutable state in Spec
- Use `+kubebuilder:validation:*` markers for all fields
- Use pointer types for optional fields: `*string`, `*int32`
- Provide defaulting via webhook or `+kubebuilder:default:=` markers
- Version with `v1alpha1` → `v1beta1` → `v1`; add conversion webhooks at v1beta1+

```go
type MyAppSpec struct {
    // +kubebuilder:validation:MinLength=1
    // +kubebuilder:validation:MaxLength=253
    Image string `json:"image"`

    // +kubebuilder:default:=1
    // +kubebuilder:validation:Minimum=0
    // +kubebuilder:validation:Maximum=100
    Replicas *int32 `json:"replicas,omitempty"`

    // +optional
    Resources corev1.ResourceRequirements `json:"resources,omitempty"`
}
```

### Status design rules
- Use `Conditions []metav1.Condition` for all status reporting
- Define a `Phase` string enum for coarse state
- Never store user input in Status

```go
// +kubebuilder:validation:Enum=Pending;Running;Failed;Succeeded
type MyAppPhase string

type MyAppStatus struct {
    // +listType=map
    // +listMapKey=type
    // +patchStrategy=merge
    // +patchMergeKey=type
    Conditions []metav1.Condition `json:"conditions,omitempty"`
    Phase      MyAppPhase         `json:"phase,omitempty"`
    ReadyReplicas int32           `json:"readyReplicas,omitempty"`
    ObservedGeneration int64      `json:"observedGeneration,omitempty"`
}
```

---

## 3. Reconciler Pattern

Read `references/reconciler-patterns.md` for advanced patterns. Core structure:

```go
type MyAppReconciler struct {
    client.Client
    Scheme   *runtime.Scheme
    Recorder record.EventRecorder
}

// +kubebuilder:rbac:groups=apps.example.com,resources=myapps,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=apps.example.com,resources=myapps/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=apps.example.com,resources=myapps/finalizers,verbs=update
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete

func (r *MyAppReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    log := log.FromContext(ctx)

    // 1. Fetch the resource
    var myApp appsv1alpha1.MyApp
    if err := r.Get(ctx, req.NamespacedName, &myApp); err != nil {
        return ctrl.Result{}, client.IgnoreNotFound(err)
    }

    // 2. Handle deletion via finalizer
    if !myApp.DeletionTimestamp.IsZero() {
        return r.handleDeletion(ctx, &myApp)
    }

    // 3. Ensure finalizer
    if !controllerutil.ContainsFinalizer(&myApp, myFinalizer) {
        controllerutil.AddFinalizer(&myApp, myFinalizer)
        return ctrl.Result{}, r.Update(ctx, &myApp)
    }

    // 4. Reconcile owned resources
    if err := r.reconcileDeployment(ctx, &myApp); err != nil {
        r.setCondition(&myApp, conditionTypeReady, metav1.ConditionFalse, "DeploymentFailed", err.Error())
        _ = r.Status().Update(ctx, &myApp)
        return ctrl.Result{RequeueAfter: 30 * time.Second}, err
    }

    // 5. Update status
    r.setCondition(&myApp, conditionTypeReady, metav1.ConditionTrue, "Reconciled", "All resources up to date")
    myApp.Status.ObservedGeneration = myApp.Generation
    return ctrl.Result{}, r.Status().Update(ctx, &myApp)
}
```

### Key reconciler rules
- **Always** use `client.IgnoreNotFound` on the initial `Get`
- **Never** return an error on NotFound for owned resources — create them instead
- **Always** update `ObservedGeneration` in status after successful reconcile
- Use `controllerutil.CreateOrUpdate` for owned resources
- Set `ctrl.Result{RequeueAfter: <duration>}` for polling-based resources
- Use `ctrl.Result{}` (no requeue) when done — rely on watches for next trigger

---

## 4. client-go / controller-runtime Usage

Read `references/client-go.md` for full API surface. Critical patterns:

### Listing with field selectors
```go
var podList corev1.PodList
if err := r.List(ctx, &podList,
    client.InNamespace(req.Namespace),
    client.MatchingFields{"status.phase": "Running"},
    client.MatchingLabels{"app": myApp.Name},
); err != nil {
    return ctrl.Result{}, err
}
```

### Setting ownership
```go
// Set controller reference so GC deletes child when parent is deleted
if err := controllerutil.SetControllerReference(&myApp, deployment, r.Scheme); err != nil {
    return ctrl.Result{}, err
}
```

### Patching status (prefer Patch over Update for status)
```go
patch := client.MergeFrom(myApp.DeepCopy())
myApp.Status.Phase = appsv1alpha1.PhaseRunning
if err := r.Status().Patch(ctx, &myApp, patch); err != nil {
    return ctrl.Result{}, err
}
```

### Server-Side Apply (preferred for owned resources in v0.15+)
```go
deployment := &appsv1.Deployment{...}
if err := r.Patch(ctx, deployment, client.Apply,
    client.FieldOwner("my-operator"),
    client.ForceOwnership,
); err != nil {
    return ctrl.Result{}, err
}
```

---

## 5. Controller Setup & Watches

```go
func (r *MyAppReconciler) SetupWithManager(mgr ctrl.Manager) error {
    // Index for field selectors
    if err := mgr.GetFieldIndexer().IndexField(
        context.Background(), &corev1.Pod{}, ".spec.nodeName",
        func(obj client.Object) []string {
            return []string{obj.(*corev1.Pod).Spec.NodeName}
        },
    ); err != nil {
        return err
    }

    return ctrl.NewControllerManagedBy(mgr).
        For(&appsv1alpha1.MyApp{}).
        Owns(&appsv1.Deployment{}).          // auto-watch owned resources
        Owns(&corev1.Service{}).
        Watches(                              // watch unowned resources
            &corev1.ConfigMap{},
            handler.EnqueueRequestsFromMapFunc(r.findAppsForConfigMap),
            builder.WithPredicates(predicate.ResourceVersionChangedPredicate{}),
        ).
        WithOptions(controller.Options{
            MaxConcurrentReconciles: 1,       // from parameter max_concurrent_reconciles
        }).
        Complete(r)
}
```

---

## 6. RBAC Markers

Always annotate reconciler methods with RBAC markers. Run `make manifests` to regenerate.

```go
// Cluster-scoped CRD
// +kubebuilder:rbac:groups=apps.example.com,resources=myapps,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=apps.example.com,resources=myapps/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=apps.example.com,resources=myapps/finalizers,verbs=update

// Core resources
// +kubebuilder:rbac:groups="",resources=configmaps,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=events,verbs=create;patch

// Leader election
// +kubebuilder:rbac:groups=coordination.k8s.io,resources=leases,verbs=get;list;watch;create;update;patch;delete
```

---

## 7. Testing

Read `references/testing.md` for envtest and mock patterns.

```go
// Use envtest for integration tests
var _ = Describe("MyApp Controller", func() {
    ctx := context.Background()

    It("should create a Deployment", func() {
        myApp := &appsv1alpha1.MyApp{
            ObjectMeta: metav1.ObjectMeta{Name: "test", Namespace: "default"},
            Spec:       appsv1alpha1.MyAppSpec{Image: "nginx:latest", Replicas: ptr.To[int32](2)},
        }
        Expect(k8sClient.Create(ctx, myApp)).To(Succeed())

        deployment := &appsv1.Deployment{}
        Eventually(func() error {
            return k8sClient.Get(ctx, types.NamespacedName{
                Name: myApp.Name, Namespace: myApp.Namespace,
            }, deployment)
        }, timeout, interval).Should(Succeed())

        Expect(*deployment.Spec.Replicas).To(Equal(int32(2)))
    })
})
```

---

## 8. Common Mistakes to Avoid

| ❌ Wrong | ✅ Right |
|----------|----------|
| `r.Update(ctx, &obj)` for status | `r.Status().Update/Patch(ctx, &obj)` |
| Ignoring resource version conflicts | Retry on `apierrors.IsConflict` |
| Returning error on NotFound child | Create the child resource |
| Storing derived state in Spec | Store in Status with Conditions |
| Using `r.Update` for owned resources | Use `controllerutil.CreateOrUpdate` or SSA |
| Direct struct copy for patch base | `obj.DeepCopy()` before mutations |
| No timeout on context | Use `context.WithTimeout` in long ops |
| Requeue on every reconcile | Only requeue when polling is needed |

---

## Reference Files

Load these when you need deeper coverage:

- `references/crd-design.md` — Full CRD schema patterns, validation, conversion webhooks
- `references/reconciler-patterns.md` — Error handling, retry strategies, event recording, finalizers
- `references/client-go.md` — Full client-go API: informers, dynamic client, typed client tricks
- `references/testing.md` — envtest setup, mocking, fuzz testing controllers
