# CRD Design Reference

## Table of Contents
1. [API Versioning Strategy](#versioning)
2. [Schema Validation Markers](#validation)
3. [Structural Schema Rules](#structural)
4. [Conversion Webhooks](#conversion)
5. [Printer Columns & Subresources](#subresources)
6. [Common Field Patterns](#patterns)

---

## 1. API Versioning Strategy {#versioning}

```
v1alpha1  → experimental, breaking changes OK
v1beta1   → stable schema, conversion webhook required
v1        → GA, backward compat required forever
```

- Add `+kubebuilder:storageversion` to exactly ONE version's type
- All other versions need conversion webhooks via `hub` pattern
- Use `sigs.k8s.io/controller-runtime/pkg/conversion` Hub interface

```go
// In v1alpha1/myapp_types.go — mark as hub
func (*MyApp) Hub() {}

// In v1beta1/myapp_conversion.go — implement spoke
func (dst *MyApp) ConvertFrom(srcRaw conversion.Hub) error {
    src := srcRaw.(*v1alpha1.MyApp)
    // ... convert fields
    return nil
}
func (src *MyApp) ConvertTo(dstRaw conversion.Hub) error {
    dst := dstRaw.(*v1alpha1.MyApp)
    // ... convert fields
    return nil
}
```

---

## 2. Schema Validation Markers {#validation}

### String validation
```go
// +kubebuilder:validation:MinLength=1
// +kubebuilder:validation:MaxLength=63
// +kubebuilder:validation:Pattern=`^[a-z][a-z0-9-]*$`
// +kubebuilder:validation:Enum=http;https;grpc
Name string `json:"name"`
```

### Numeric validation
```go
// +kubebuilder:validation:Minimum=1
// +kubebuilder:validation:Maximum=65535
// +kubebuilder:validation:MultipleOf=8
Port int32 `json:"port"`
```

### List validation
```go
// +kubebuilder:validation:MinItems=1
// +kubebuilder:validation:MaxItems=10
// +listType=set
Tags []string `json:"tags,omitempty"`

// For maps-as-lists (use key field):
// +listType=map
// +listMapKey=name
Containers []ContainerSpec `json:"containers,omitempty"`
```

### Cross-field validation (CEL — k8s 1.25+)
```go
// +kubebuilder:validation:XValidation:rule="self.minReplicas <= self.maxReplicas",message="minReplicas must be <= maxReplicas"
type ScalingPolicy struct {
    MinReplicas int32 `json:"minReplicas"`
    MaxReplicas int32 `json:"maxReplicas"`
}
```

### Immutability
```go
// +kubebuilder:validation:XValidation:rule="self == oldSelf",message="storageClass is immutable"
StorageClass string `json:"storageClass"`
```

---

## 3. Structural Schema Rules {#structural}

Kubernetes requires ALL CRD schemas to be "structural" (no `x-kubernetes-preserve-unknown-fields: true` at nested levels unless intentional).

Rules:
- Every field must have a type
- No `additionalProperties: true` unless using `map[string]interface{}`
- Use `+kubebuilder:pruning:PreserveUnknownFields` only at top-level `runtime.RawExtension` fields

```go
// For arbitrary JSON (e.g., plugin config):
// +kubebuilder:pruning:PreserveUnknownFields
Config *runtime.RawExtension `json:"config,omitempty"`
```

---

## 4. Conversion Webhooks {#conversion}

Register in main.go:
```go
if err = (&appsv1alpha1.MyApp{}).SetupWebhookWithManager(mgr); err != nil {
    setupLog.Error(err, "unable to create webhook", "webhook", "MyApp")
    os.Exit(1)
}
```

Certificate management options (pick one):
1. `cert-manager` — add `// +kubebuilder:webhook:...` markers + CertificateRequest
2. `controller-runtime/pkg/certwatcher` — file-based hot reload
3. `kubebuilder` built-in with `--cert-manager` flag

---

## 5. Printer Columns & Subresources {#subresources}

```go
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:subresource:scale:specpath=.spec.replicas,statuspath=.status.replicas,selectorpath=.status.selector
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=`.status.phase`,description="Current phase"
// +kubebuilder:printcolumn:name="Ready",type=string,JSONPath=`.status.conditions[?(@.type=="Ready")].status`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`
// +kubebuilder:resource:scope=Namespaced,shortName=ma;mas,categories=mygroup
```

Scale subresource enables `kubectl scale` on custom resources — only add if the resource has a meaningful replica count.

---

## 6. Common Field Patterns {#patterns}

### Image reference
```go
type ImageSpec struct {
    // +kubebuilder:validation:MinLength=1
    Repository string `json:"repository"`
    // +kubebuilder:default:="latest"
    Tag string `json:"tag,omitempty"`
    // +kubebuilder:validation:Enum=Always;Never;IfNotPresent
    // +kubebuilder:default:=IfNotPresent
    PullPolicy corev1.PullPolicy `json:"pullPolicy,omitempty"`
}
```

### Resource requirements (reuse core types)
```go
Resources corev1.ResourceRequirements `json:"resources,omitempty"`
```

### Service reference
```go
type ServiceRef struct {
    // +kubebuilder:validation:MinLength=1
    Name string `json:"name"`
    // +kubebuilder:validation:Minimum=1
    // +kubebuilder:validation:Maximum=65535
    Port int32 `json:"port"`
}
```

### Condition helper
```go
func setCondition(obj *MyApp, condType string, status metav1.ConditionStatus, reason, msg string) {
    meta.SetStatusCondition(&obj.Status.Conditions, metav1.Condition{
        Type:               condType,
        Status:             status,
        Reason:             reason,
        Message:            msg,
        ObservedGeneration: obj.Generation,
    })
}
```

### Standard condition types to define
```go
const (
    ConditionTypeReady       = "Ready"
    ConditionTypeProgressing = "Progressing"
    ConditionTypeDegraded    = "Degraded"
    ConditionTypeAvailable   = "Available"
)
```
