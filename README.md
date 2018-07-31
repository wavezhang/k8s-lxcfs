# 使用lxcfs增强容器的隔离性

### 安装lxcfs（所有节点上执行）

```
wget https://copr-be.cloud.fedoraproject.org/results/ganto/lxd/epel-7-x86_64/00486278-lxcfs/lxcfs-2.0.5-3.el7.centos.x86_64.rpm
yum install lxcfs-2.0.5-3.el7.centos.x86_64.rpm  

```
### 启动lxcfs（所有节点上执行）

```
systemctl enable lxcfs
systemctl start lxcfs
```

### 测试

```
docker run -it -m 256m --rm \
      -v /var/lib/lxcfs/proc/cpuinfo:/proc/cpuinfo:rw \
      -v /var/lib/lxcfs/proc/diskstats:/proc/diskstats:rw \
      -v /var/lib/lxcfs/proc/meminfo:/proc/meminfo:rw \
      -v /var/lib/lxcfs/proc/stat:/proc/stat:rw \
      -v /var/lib/lxcfs/proc/swaps:/proc/swaps:rw \
      -v /var/lib/lxcfs/proc/uptime:/proc/uptime:rw \
      ubuntu:16.04 free -m
```


那么如何在Kubernetes中使用 lxcfs 呢？两种方法，一种是initializer，还有一种是PodPreset。PodPreset存在namespace隔离。
# 方法一：启用initializer
可以用于对资源创建进行拦截和注入处理，我们可以借助它优雅地完成对lxcfs文件的自动化挂载

### 打开apiserver的开关
apiserver中添加如下配置     
```
--admission-control=Initializers    
--runtime-config=admissionregistration.k8s.io/v1alpha1=true
```
### yaml文件部署intializer   
        
    kubectl apply -f lxcfs-initializer.yaml

cat lxcfs-initializer.yaml

```
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: lxcfs-initializer-default
  namespace: default
rules:
- apiGroups: ["*"]
  resources: ["deployments"]
  verbs: ["initialize", "patch", "watch", "list"]
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: lxcfs-initializer-service-account
  namespace: default
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: lxcfs-initializer-role-binding
subjects:
- kind: ServiceAccount
  name: lxcfs-initializer-service-account
  namespace: default
roleRef:
  kind: ClusterRole
  name: lxcfs-initializer-default
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  initializers:
    pending: []
  labels:
    app: lxcfs-initializer
  name: lxcfs-initializer
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: lxcfs-initializer
      name: lxcfs-initializer
    spec:
      serviceAccountName: lxcfs-initializer-service-account
      containers:
        - name: lxcfs-initializer
          image: registry.cn-hangzhou.aliyuncs.com/denverdino/lxcfs-initializer:0.0.2
          imagePullPolicy: Always
          args:
            - "-annotation=initializer.kubernetes.io/lxcfs"
            - "-require-annotation=true"
---
apiVersion: admissionregistration.k8s.io/v1alpha1
kind: InitializerConfiguration
metadata:
  name: lxcfs.initializer
initializers:
  - name: lxcfs.initializer.kubernetes.io
    rules:
      - apiGroups:
          - "*"
        apiVersions:
          - "*"
        resources:
          - deployments
```
### 测试

```
cat test.yaml
```
```
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  annotations:
    "initializer.kubernetes.io/lxcfs": "true"
  labels:
    app: web
  name: web
  namespace: msxutest
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: web
      name: web
    spec:
      containers:
        - name: web
          image: 172.16.59.153/base/centos:7
          command:
          - sleep
          - "3500"
          imagePullPolicy: Always
          resources:
            requests:
              memory: "256Mi"
              cpu: "500m"
            limits:
              memory: "256Mi"
              cpu: "500m"
```
```
kubectl apply -f test.yaml
```

# 方法二：启用PodPreset（仅master上执行）
可以用PodPreset让每个 pod 都默认绑定 lxcfs 提供的路径 。

    notes: 此方法PodPreset有namespaces的区分，不同的namespaces，PodPreset无法起作用。
### 打开apiserver特性开关
1. API Server 启动参数添加  ```--runtime-config settings.k8s.io/v1alpha1=true```
2. API Server的```--enable-admission-control``` 配置项中包含 ```PodPreset```

### k8s 部署（仅master上执行）
```
cat lxcfs.yaml
```
```
apiVersion: settings.k8s.io/v1alpha1
kind: PodPreset
metadata:
  name: lxcfs
spec:
  selector:
    matchLabels:
      lxcfs: enable
  volumeMounts:
    - mountPath: /proc/cpuinfo
      name: cpuinfo
    - mountPath: /proc/diskstats
      name: diskstats
    - mountPath: /proc/meminfo
      name: meminfo
    - mountPath: /proc/stat
      name: stat
    - mountPath: /proc/swaps
      name: swaps
    - mountPath: /proc/uptime
      name: uptime
  volumes:
  - name: cpuinfo
    hostPath:
      path: /var/lib/lxcfs/proc/cpuinfo
      type: File
  - name: diskstats
    hostPath:
      path: /var/lib/lxcfs/proc/diskstats
      type: File
  - name: meminfo
    hostPath:
      path: /var/lib/lxcfs/proc/meminfo
      type: File
  - name: stat
    hostPath:
      path: /var/lib/lxcfs/proc/stat
      type: File
  - name: swaps
    hostPath:
      path: /var/lib/lxcfs/proc/swaps
      type: File
  - name: uptime
    hostPath:
      path: /var/lib/lxcfs/proc/uptime
      type: File

```
```
# kubectl apply -f lxcfs.yaml 
podpreset.settings.k8s.io "lxcfs" created
```


### 测试


```
cat lxcfs-pod.yaml
```
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: lxcfs-test
  labels:
    lxcfs: enable
spec:
  restartPolicy: Never
  containers:
  - name: lxcfs-test
    image: "ubuntu:16.04"
    resources:
      limits:
        memory: "1Gi"
        cpu: 100m
    command: ["/bin/sh", "-c", "sleep 360000"]
```
```
kubectl create -f lxcfs-pod.yaml
```
```
kubectl exec lxcfs-test -- free -h
```

### 脚本部署
1. 在所有节点上执行```sh init.sh```.
2. 在master节点上执行 ```sh install.sh```.
