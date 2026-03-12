# Testing Kubernetes Operators

## Table of Contents
1. [envtest Setup](#envtest)
2. [Ginkgo + Gomega Patterns](#ginkgo)
3. [Fake Client Unit Tests](#unit)
4. [Webhook Testing](#webhook)
5. [Fuzz Testing](#fuzz)
6. [Test Helpers](#helpers)

---

## 1. envtest Setup {#envtest}

envtest runs a real API server + etcd locally without a cluster.

### suite_test.go boilerplate
```go
package controller_test

import (
    "context"
    "path/filepath"
    "testing"
    "time"

    . "github.com/onsi/ginkgo/v2"
    . "github.com/onsi/gomega"
    appsv1 "k8s.io/api/apps/v1"
    "k8s.io/client-go/kubernetes/scheme"
    ctrl "sigs.k8s.io/controller-runtime"
    "sigs.k8s.io/controller-runtime/pkg/client"
    "sigs.k8s.io/controller-runtime/pkg/envtest"
    logf "sigs.k8s.io/controller-runtime/pkg/log"
    "sigs.k8s.io/controller-runtime/pkg/log/zap"

    appsv1alpha1 "github.com/org/my-operator/api/v1alpha1"
)

const (
    timeout  = time.Second * 10
    interval = time.Millisecond * 250
)

var (
    k8sClient  client.Client
    testEnv    *envtest.Environment
    ctx        context.Context
    cancel     context.CancelFunc
)

func TestControllers(t *testing.T) {
    RegisterFailHandler(Fail)
    RunSpecs(t, "Controller Suite")
}

var _ = BeforeSuite(func() {
    logf.SetLogger(zap.New(zap.WriteTo(GinkgoWriter), zap.UseDevMode(true)))
    ctx, cancel = context.WithCancel(context.TODO())

    testEnv = &envtest.Environment{
        CRDDirectoryPaths:     []string{filepath.Join("..", "..", "config", "crd", "bases")},
        ErrorIfCRDPathMissing: true,
    }

    cfg, err := testEnv.Start()
    Expect(err).NotTo(HaveOccurred())

    err = appsv1alpha1.AddToScheme(scheme.Scheme)
    Expect(err).NotTo(HaveOccurred())

    k8sClient, err = client.New(cfg, client.Options{Scheme: scheme.Scheme})
    Expect(err).NotTo(HaveOccurred())

    mgr, err := ctrl.NewManager(cfg, ctrl.Options{Scheme: scheme.Scheme})
    Expect(err).NotTo(HaveOccurred())

    err = (&MyAppReconciler{
        Client:   mgr.GetClient(),
        Scheme:   mgr.GetScheme(),
        Recorder: mgr.GetEventRecorderFor("test"),
    }).SetupWithManager(mgr)
    Expect(err).NotTo(HaveOccurred())

    go func() {
        defer GinkgoRecover()
        err = mgr.Start(ctx)
        Expect(err).NotTo(HaveOccurred())
    }()
})

var _ = AfterSuite(func() {
    cancel()
    Expect(testEnv.Stop()).To(Succeed())
})
```

### Makefile target to download envtest binaries
```makefile
ENVTEST_K8S_VERSION = 1.31.0

.PHONY: envtest
envtest:
    $(shell go env GOPATH)/bin/setup-envtest use $(ENVTEST_K8S_VERSION) \
        --bin-dir $(shell go env GOPATH)/bin -p path
```

---

## 2. Ginkgo + Gomega Patterns {#ginkgo}

```go
var _ = Describe("MyApp Controller", func() {
    var (
        myApp     *appsv1alpha1.MyApp
        namespace string
    )

    BeforeEach(func() {
        namespace = "test-" + randString(5)
        ns := &corev1.Namespace{ObjectMeta: metav1.ObjectMeta{Name: namespace}}
        Expect(k8sClient.Create(ctx, ns)).To(Succeed())

        myApp = &appsv1alpha1.MyApp{
            ObjectMeta: metav1.ObjectMeta{
                Name:      "test-app",
                Namespace: namespace,
            },
            Spec: appsv1alpha1.MyAppSpec{
                Image:    "nginx:latest",
                Replicas: ptr.To[int32](2),
            },
        }
    })

    AfterEach(func() {
        Expect(k8sClient.Delete(ctx, myApp)).To(Succeed())
        // Wait for deletion to propagate
        Eventually(func() error {
            return k8sClient.Get(ctx, client.ObjectKeyFromObject(myApp), myApp)
        }, timeout, interval).Should(MatchError(ContainSubstring("not found")))
    })

    Context("when a MyApp is created", func() {
        It("should create an owned Deployment", func() {
            Expect(k8sClient.Create(ctx, myApp)).To(Succeed())

            deploy := &appsv1.Deployment{}
            Eventually(func() error {
                return k8sClient.Get(ctx, types.NamespacedName{
                    Name: myApp.Name, Namespace: namespace,
                }, deploy)
            }, timeout, interval).Should(Succeed())

            Expect(*deploy.Spec.Replicas).To(Equal(int32(2)))
            Expect(deploy.OwnerReferences).To(HaveLen(1))
            Expect(deploy.OwnerReferences[0].Name).To(Equal(myApp.Name))
        })

        It("should set Ready condition to True", func() {
            Expect(k8sClient.Create(ctx, myApp)).To(Succeed())

            Eventually(func(g Gomega) {
                g.Expect(k8sClient.Get(ctx, client.ObjectKeyFromObject(myApp), myApp)).To(Succeed())
                condition := meta.FindStatusCondition(myApp.Status.Conditions, "Ready")
                g.Expect(condition).NotTo(BeNil())
                g.Expect(condition.Status).To(Equal(metav1.ConditionTrue))
            }, timeout, interval).Should(Succeed())
        })
    })
})
```

**Key Gomega tips:**
- Use `Eventually(func(g Gomega) {...})` (with `g` param) for composite assertions — all inner `g.Expect` calls are retried atomically
- Use `Consistently` to assert something never happens over a duration
- Use `HaveCondition` (custom matcher) to test status conditions cleanly

---

## 3. Fake Client Unit Tests {#unit}

Unit tests are faster but less realistic. Use for testing reconcile logic in isolation.

```go
func TestReconcileDeployment(t *testing.T) {
    g := gomega.NewWithT(t)

    myApp := &appsv1alpha1.MyApp{
        ObjectMeta: metav1.ObjectMeta{
            Name: "test", Namespace: "default",
            Generation: 1,
        },
        Spec: appsv1alpha1.MyAppSpec{Image: "nginx:latest"},
    }

    s := runtime.NewScheme()
    _ = appsv1alpha1.AddToScheme(s)
    _ = appsv1.AddToScheme(s)

    c := fake.NewClientBuilder().
        WithScheme(s).
        WithObjects(myApp).
        WithStatusSubresource(&appsv1alpha1.MyApp{}).
        Build()

    r := &MyAppReconciler{Client: c, Scheme: s}

    _, err := r.Reconcile(context.Background(), reconcile.Request{
        NamespacedName: types.NamespacedName{Name: "test", Namespace: "default"},
    })
    g.Expect(err).To(gomega.BeNil())

    // Verify deployment was created
    deploy := &appsv1.Deployment{}
    g.Expect(c.Get(context.Background(),
        types.NamespacedName{Name: "test", Namespace: "default"}, deploy,
    )).To(gomega.Succeed())
    g.Expect(deploy.Spec.Template.Spec.Containers[0].Image).To(gomega.Equal("nginx:latest"))
}
```

---

## 4. Webhook Testing {#webhook}

```go
var _ = Describe("MyApp Webhook", func() {
    It("rejects empty image", func() {
        myApp := &appsv1alpha1.MyApp{
            ObjectMeta: metav1.ObjectMeta{Name: "bad", Namespace: "default"},
            Spec:       appsv1alpha1.MyAppSpec{Image: ""},
        }
        err := k8sClient.Create(ctx, myApp)
        Expect(err).To(HaveOccurred())
        Expect(err.Error()).To(ContainSubstring("image"))
    })

    It("defaults replicas to 1", func() {
        myApp := &appsv1alpha1.MyApp{
            ObjectMeta: metav1.ObjectMeta{Name: "no-replicas", Namespace: "default"},
            Spec:       appsv1alpha1.MyAppSpec{Image: "nginx:latest"},
        }
        Expect(k8sClient.Create(ctx, myApp)).To(Succeed())
        Expect(*myApp.Spec.Replicas).To(Equal(int32(1)))
    })
})
```

For webhook envtest, configure TLS in the test environment:
```go
testEnv = &envtest.Environment{
    WebhookInstallOptions: envtest.WebhookInstallOptions{
        Paths: []string{filepath.Join("..", "..", "config", "webhook")},
    },
}
```

---

## 5. Fuzz Testing {#fuzz}

```go
// fuzz_test.go
func FuzzReconcile(f *testing.F) {
    f.Add("nginx:latest", int32(1))

    f.Fuzz(func(t *testing.T, image string, replicas int32) {
        if image == "" || replicas < 0 || replicas > 100 {
            return // skip invalid inputs
        }
        myApp := &appsv1alpha1.MyApp{
            ObjectMeta: metav1.ObjectMeta{Name: "fuzz", Namespace: "default"},
            Spec:       appsv1alpha1.MyAppSpec{Image: image, Replicas: &replicas},
        }

        c := fake.NewClientBuilder().WithScheme(s).WithObjects(myApp).Build()
        r := &MyAppReconciler{Client: c, Scheme: s}
        _, err := r.Reconcile(context.Background(), reconcile.Request{
            NamespacedName: types.NamespacedName{Name: "fuzz", Namespace: "default"},
        })
        if err != nil {
            t.Errorf("reconcile returned unexpected error: %v", err)
        }
    })
}
```

---

## 6. Test Helpers {#helpers}

```go
// helpers_test.go

// Wait for an object condition
func waitForCondition(ctx context.Context, obj client.Object, condType string, status metav1.ConditionStatus) {
    GinkgoHelper()
    Eventually(func(g Gomega) {
        g.Expect(k8sClient.Get(ctx, client.ObjectKeyFromObject(obj), obj)).To(Succeed())
        c := meta.FindStatusCondition(
            obj.(*appsv1alpha1.MyApp).Status.Conditions, condType,
        )
        g.Expect(c).NotTo(BeNil())
        g.Expect(c.Status).To(Equal(status))
    }, timeout, interval).Should(Succeed())
}

// Create object and clean up after test
func createAndCleanup(ctx context.Context, obj client.Object) {
    GinkgoHelper()
    Expect(k8sClient.Create(ctx, obj)).To(Succeed())
    DeferCleanup(func() {
        _ = k8sClient.Delete(ctx, obj)
    })
}

// Random string for namespaces
func randString(n int) string {
    const letters = "abcdefghijklmnopqrstuvwxyz"
    b := make([]byte, n)
    for i := range b {
        b[i] = letters[rand.Intn(len(letters))]
    }
    return string(b)
}
```
