# client-go & controller-runtime Client Reference

## Table of Contents
1. [Typed Client CRUD](#typed-crud)
2. [List Options](#list-options)
3. [Field Indexers](#indexers)
4. [Unstructured & Dynamic Client](#dynamic)
5. [Informer Cache Internals](#cache)
6. [Subresource Clients](#subresource)
7. [Fake Client for Testing](#fake)

---

## 1. Typed Client CRUD {#typed-crud}

```go
// GET
var obj appsv1alpha1.MyApp
err := r.Get(ctx, types.NamespacedName{Name: "foo", Namespace: "default"}, &obj)

// LIST
var list appsv1alpha1.MyAppList
err = r.List(ctx, &list, client.InNamespace("default"))

// CREATE
err = r.Create(ctx, &obj)

// UPDATE (full object — increments resourceVersion)
err = r.Update(ctx, &obj)

// PATCH (preferred — only send diff)
patch := client.MergeFrom(obj.DeepCopy())
obj.Labels["foo"] = "bar"
err = r.Patch(ctx, &obj, patch)

// DELETE
err = r.Delete(ctx, &obj, client.PropagationPolicy(metav1.DeletePropagationForeground))

// STATUS UPDATE (uses /status subresource — does not change spec)
err = r.Status().Update(ctx, &obj)
err = r.Status().Patch(ctx, &obj, patch)
```

---

## 2. List Options {#list-options}

```go
r.List(ctx, &list,
    // Namespace
    client.InNamespace("production"),

    // Label selector
    client.MatchingLabels{"app": "nginx", "tier": "frontend"},
    client.HasLabels{"app"},

    // Field selector (only works for indexed fields or built-ins)
    client.MatchingFields{"spec.nodeName": "node-1"},

    // Limit + continue (pagination)
    client.Limit(100),
    client.Continue(list.Continue),
)
```

### Built-in indexable fields (no setup needed):
- `metadata.name`
- `metadata.namespace`
- `spec.nodeName` (Pod)
- `spec.serviceAccountName` (Pod)
- `status.phase` (Pod)

---

## 3. Field Indexers {#indexers}

Register in `SetupWithManager` or on manager start:

```go
const deploymentOwnerKey = ".metadata.controller"

func (r *MyAppReconciler) SetupWithManager(mgr ctrl.Manager) error {
    if err := mgr.GetFieldIndexer().IndexField(
        context.Background(),
        &appsv1.Deployment{},
        deploymentOwnerKey,
        func(rawObj client.Object) []string {
            deploy := rawObj.(*appsv1.Deployment)
            owner := metav1.GetControllerOf(deploy)
            if owner == nil || owner.APIVersion != appsv1alpha1.GroupVersion.String() {
                return nil
            }
            return []string{owner.Name}
        },
    ); err != nil {
        return err
    }

    return ctrl.NewControllerManagedBy(mgr).For(&appsv1alpha1.MyApp{}).Complete(r)
}

// Then query:
var deployments appsv1.DeploymentList
r.List(ctx, &deployments,
    client.InNamespace(myApp.Namespace),
    client.MatchingFields{deploymentOwnerKey: myApp.Name},
)
```

---

## 4. Unstructured & Dynamic Client {#dynamic}

Use when you need to work with CRDs that aren't registered in your scheme:

```go
import "k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"

obj := &unstructured.Unstructured{}
obj.SetGroupVersionKind(schema.GroupVersionKind{
    Group:   "networking.istio.io",
    Version: "v1alpha3",
    Kind:    "VirtualService",
})

if err := r.Get(ctx, types.NamespacedName{Name: "my-vs", Namespace: "default"}, obj); err != nil {
    return ctrl.Result{}, err
}

// Read nested field
host, found, err := unstructured.NestedString(obj.Object, "spec", "hosts", "0")

// Set nested field
unstructured.SetNestedField(obj.Object, "new-host.example.com", "spec", "hosts", "0")
```

### Dynamic client (raw REST, bypasses cache)
```go
import "k8s.io/client-go/dynamic"

dynClient, err := dynamic.NewForConfig(mgr.GetConfig())

gvr := schema.GroupVersionResource{
    Group: "networking.istio.io", Version: "v1alpha3", Resource: "virtualservices",
}
list, err := dynClient.Resource(gvr).Namespace("default").List(ctx, metav1.ListOptions{})
```

---

## 5. Informer Cache Internals {#cache}

The controller-runtime `Client` reads from a **local in-memory cache** backed by informers.
Writes (`Create`, `Update`, `Patch`, `Delete`) go directly to the API server.

**Implications:**
- Reads are eventually consistent — there's a brief lag after writes
- After a `Create`, an immediate `Get` might return NotFound — use `Eventually` in tests
- The cache is namespace-aware; unset namespace gets all namespaces
- For consistent reads, use `client.Reader` (bypasses cache, hits API server directly):

```go
// Inject the uncached reader
type MyReconciler struct {
    client.Client
    APIReader client.Reader // mgr.GetAPIReader()
}

// Use for critical reads where consistency is required
var freshObj appsv1alpha1.MyApp
err := r.APIReader.Get(ctx, req.NamespacedName, &freshObj)
```

### Cache options (scope what gets cached)
```go
mgr, err := ctrl.NewManager(cfg, ctrl.Options{
    Cache: cache.Options{
        // Only cache specific namespaces
        DefaultNamespaces: map[string]cache.Config{
            "production": {},
            "staging":    {},
        },
        // Transform objects before caching (strip managed fields to save memory)
        DefaultTransform: func(i interface{}) (interface{}, error) {
            if obj, ok := i.(metav1.Object); ok {
                obj.SetManagedFields(nil)
            }
            return i, nil
        },
    },
})
```

---

## 6. Subresource Clients {#subresource}

```go
// Exec into a pod (low-level REST)
import "k8s.io/client-go/tools/remotecommand"

restClient, _ := rest.RESTClientFor(mgr.GetConfig())
req := restClient.Post().
    Resource("pods").
    Name(pod.Name).
    Namespace(pod.Namespace).
    SubResource("exec").
    VersionedParams(&corev1.PodExecOptions{
        Command: []string{"/bin/sh", "-c", "echo hello"},
        Stdin:   false,
        Stdout:  true,
        Stderr:  true,
    }, scheme.ParameterCodec)

exec, _ := remotecommand.NewSPDYExecutor(mgr.GetConfig(), "POST", req.URL())
exec.StreamWithContext(ctx, remotecommand.StreamOptions{Stdout: os.Stdout})
```

---

## 7. Fake Client for Testing {#fake}

```go
import "sigs.k8s.io/controller-runtime/pkg/client/fake"

func newFakeClient(objs ...client.Object) client.Client {
    scheme := runtime.NewScheme()
    _ = appsv1alpha1.AddToScheme(scheme)
    _ = appsv1.AddToScheme(scheme)
    _ = corev1.AddToScheme(scheme)

    return fake.NewClientBuilder().
        WithScheme(scheme).
        WithObjects(objs...).
        WithStatusSubresource(&appsv1alpha1.MyApp{}). // enable status updates
        Build()
}

// Usage in unit test
func TestReconciler(t *testing.T) {
    myApp := &appsv1alpha1.MyApp{
        ObjectMeta: metav1.ObjectMeta{Name: "test", Namespace: "default"},
        Spec:       appsv1alpha1.MyAppSpec{Image: "nginx:latest"},
    }

    r := &MyAppReconciler{
        Client: newFakeClient(myApp),
        Scheme: scheme,
    }

    result, err := r.Reconcile(context.Background(), reconcile.Request{
        NamespacedName: types.NamespacedName{Name: "test", Namespace: "default"},
    })
    assert.NoError(t, err)
    assert.Equal(t, ctrl.Result{}, result)
}
```
