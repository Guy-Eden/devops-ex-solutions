# Devops Exercise Solutions

## Stage 0 - Preparing your environment:

1. The kubernetes solution I'm using is Docker Desktop Kubernetes. You can install it _[here](https://www.docker.com/products/docker-desktop/)_.
2. While docker desktop is downloading and installing, create a _[docker hub account](https://hub.docker.com/signup)_ (You're going to need it when it's time to push your image to docker hub).
3. When docker desktop is done installing - luanch it and sign in with the docker hub account you've just opened.

    _**Make sure to enable Kubernetes in the settings**_
4. **(Optional)** Install a version control management system - In this case I'm using _[git](https://git-scm.com/downloads)_
5. Clone the exercise onto your local machine (if you've skipped step 4, just download the repo):
    ```bash
    git clone https://gitlab.com/iyehuda/devops-exercise.git
    ```
6. Install an IDE - I recommend _[VS Code](https://code.visualstudio.com/download)_ since it has an official microsoft docker extension that makes life a whole lot easier.
7. Install the docker extension: `ms-azuretools.vscode-docker`

Now your environment should be ready for the exercise.

## Stage 1 - Application Deployment
### Step 1 - Building the docker image and pushing it to docker hub:

1. Open the repo you have cloned in VS Code. 
2. Right-Click the `Dockerfile` 
3. Select `Build Image...`
    
    **Note:** The image name will be the same as the folder you've opened - in this case the folder's name is `devopsexercise` since that's the name of the repo we've cloned. If you have downloaded the repo manually it might be different for you.
4. As the build is running - create a repository in docker hub named `coin-master-api`.
5. After the build has finished - View the image in the docker desktop UI under Images > Local.
    
    The current name of the image is `devopsexercise:latest`.
    Before we push it onto docker hub we would like to change the name, since the Makefile is built to work with the image name `coin-master-api:latest`.
    
    To change the name run the following command:
    ```
    docker tag devopsexcercise:latest <Your dockerhub namespace>/coin-master-api:latest
    ```
6. Push the image onto your new repository:
    ```docker
    docker push <Your dockerhub namespace>/coin-master-api:latest
    ```
### Step 2 - Deploy a Kubernetes Cluster

We have chosen docker for desktop in stage 0.

### Step 3 - Deploy a workload on the Kubernetes cluster

This step requires 2 sub steps:
* Expose the API with an ingress controller.
* Use a kubernetes secret to keep the API Key.

Let's Start with the key.

**Using a kubernetes secret to keep the API Key**

There are a few ways to create a kubernetes secret, 
for this excercise I'm creating it from a YAML file:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: api-key
type: Opaque
data:
  exchange_api_key: <Key in base64>
```
Save this yaml document as coin-master-api.yaml, and run the following line to create the secret:
```bash
kubectl apply -f coin-master-api.yaml  
```
To make sure the secret was created, run:
```bash
kubectl get secret api-key -o yaml  
```
Expected output:
```yaml
apiVersion: v1
data:
  exchange_api_key: <Key in base64>
kind: Secret
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"v1","data":{"exchange_api_key":<Key in base64>},"kind":"Secret","metadata":{"annotations":{},"name":"api-key","namespace":"default"},"type":"Opaque"}
  creationTimestamp: "2022-03-22T19:49:48Z"
  name: api-key
  namespace: default
  resourceVersion: "5718"
  uid: 3b8c3003-7fa1-4be4-a5c2-d33f662a1745
type: Opaque
```

That's great!
Now we have the key as a secret, we have a ready docker image, and we have an API url.

**Exposing the API with an ingress controller**
Let's plan the deployment, remember, the requirement is to expose the API over ingress.

That means we're going to need 4 components (at least) in our architecture:
* A deployment
* An internal service
* An ingress controller
* An ingress resource


For the deployment configuration I'm using the image we have built, appending to the file we have created for the key:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coin-master-deployment
  labels:
    app: coin-master-api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: coin-master-api
  template:
    metadata:
      name: coin-master-api
      labels:
            run: coin-master-api
            app: coin-master-api
    spec:
      containers:
      - name: coin-master-api
        image: guyseaneden/coin-master-api
        ports:
        - containerPort: 8000
        env:
          - name: EXCHANGE_API_KEY
            valueFrom:
              secretKeyRef:
                name: api-key
                key: exchange_api_key
          - name: EXCHANGE_BASE_URL
            value: "https://v6.exchangerate-api.com"
```
_Notice how the port is specified, and the secret is injected into the environment variables._


To make sure the environment variables got through, run:
```
kubectl exec coin-master-api -- printenv
```
If you got everything right you should see these lines in the output:
```
EXCHANGE_API_KEY=<Actual Key here>
EXCHANGE_BASE_URL=https://v6.exchangerate-api.com
```

To allow the pod to be exposed we must connect it to a service.
Since were going to use ingress, we'll use a ClusterIP internal service.
As usual, appending into coin-master-api.yaml:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: coin-master-api-internal-service
  labels:
        run: coin-master-api-internal-service
spec:
  type: ClusterIP
  selector:
    app: coin-master-api
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8000
```
_Notice that the service is configured to listen on port 80, and uses port 8000 to transfer the requests to the pod._


For the ingress controller I'm using _[kubernetes/ingress-nginx](https://kubernetes.github.io/ingress-nginx/)_.
You can quilckly install it by running:
```
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.1.2/deploy/static/provider/cloud/deploy.yaml
```
And after a minute or two you can verify that the ingress controller pod is running by executing the following command:
```
kubectl get pods --namespace=ingress-nginx
```
Now you can see an ingress class was created - run:
```
kubectl get ingressclass
```

To connect the ingress controller to the service, create an ingress resource.
Append to coin-master-api.yaml:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: coin-master-api-ingress
spec:
  rules:
  - host: coin-master-api.com
    http:
      paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: coin-master-api-internal-service
              port: 
                number: 80
  ingressClassName: nginx
```
_Notice the service name is specified, and **most importantly - the ingressClassName**._
_Also notice the host key. We'll have to make sure it's linked to the ingress's IP Adress._


## Almost Done!
Run the following command to create the stack.
```
kubectl apply -f coin-master-api.yaml  
```
Check your ingress resource's IP Address:
```
kubectl get ingress
```
Since I used Kubernetes locally with docker for desktop, the address my ingress got is my localhost address.
Define the address in your hosts file, matched by the host you specified for the ingress resource:
```
127.0.0.0   coin-master-api.com
```

Now test your API by running:
```bash
curl http://coin-master-api.com/rate/USD/ILS
```
Expected output:
```
{"rate":3.23310925}
```
_You can also simply browse to the URL using your preffered web browser._


## Stage 2 - Automate application provisioning with Terraform

For this stage, I had to migrate to _[kind](https://kind.sigs.k8s.io/)_ Due to the current kubernetes version on docker for desktop being 1.22.5. The latest terraform provider relys on API directories that have been removed since kubernetes v1.22. Docker for desktop does not allow the user to change the k8s version.

![](assets\kubernetesAPIRemovals.png)

### Step 1 - Creating a kind cluster
You can create a kind cluster with a simple command:
```
kind create cluster
```

But since i'd like to modify the cluster's configuration i'll use a configuration file to specify 
kubernetes version to be pre v1.22.
Notice 2 important definitions:

* image - this is the critical attribute that allows me to change the image of my kubernetes cluster.
* extraPortMappings - since kind uses docker to run the cluster, I need to map the ports i'm using.

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  image: kindest/node:v1.21.10@sha256:84709f09756ba4f863769bdcabe5edafc2ada72d3c8c44d6515fc581b66b029c
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
```

This config file is a modified version of the config file in _[this guide](https://dustinspecker.com/posts/test-ingress-in-kind/)_.

Next, run:
```
kind create cluster --config kind_basic_config.yaml
```

Next, install nginx-ingress on your kubernetes cluster:
```
kubectl apply --filename https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/kind/deploy.yaml
```
You might need to wait a couple of minutes for the services to start up.

### Step 2 - Installing and configuring Terraform Kubernetes provider
You can download Terraform CLI _[here](https://www.terraform.io/downloads)_.

I'm using _Terraform v1.1.7 on windows_amd64_.

Next, i'll define a basic tf file with a tfvars file:
```js
# kubernetes.tf file
terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

variable "host" {
  type = string
}

variable "client_certificate" {
  type = string
}

variable "client_key" {
  type = string
}

variable "cluster_ca_certificate" {
  type = string
}

variable "api_key" {
  type = string
}

variable "api_url" {
  type = string
}

variable "replica_num" {
  type = number
}

provider "kubernetes" {
  host = var.host

  client_certificate     = base64decode(var.client_certificate)
  client_key             = base64decode(var.client_key)
  cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
}
```

_Note: Every variable mentioned above will be present in the tfvars file, you can find client_certificate, client_key, and cluster_ca_certificate in your kubeconfig file, and you can find your host endpoint by running:_
```
kubectl cluster-info --context kind-kind
```
Additionally, make sure to use the raw api_key here, since terraform will encode it in base64 for you.
```js
# terraform.tfvars file
host                   = "https://127.0.0.1:[REDACTED]"
client_certificate     = "[REDACTED]"
client_key             = "[REDACTED]"
cluster_ca_certificate = "[REDACTED]"
api_key                = "[REDACTED]"
api_url                = "https://v6.exchangerate-api.com"
replica_num            = 2
```

Verify Terraform can connect to your k8s cluster by running:
```
terraform plan kubernetes.tf
```

### Step 3 - Converting yaml files to TF files

Next, we'll convert our existing yaml file to the TF format, using a utility called _[k2tf](https://github.com/sl1pm4t/k2tf/releases)_:

```
k2tf -f coin-master-api.yaml
```
Output:
```js
resource "kubernetes_secret" "api_key" {
  metadata {
    name = "api-key"
  }

  data = {
    exchange_api_key = "[REDACTED]"
  }

  type = "Opaque"
}

resource "kubernetes_deployment" "coin_master_deployment" {
  metadata {
    name = "coin-master-deployment"

    labels = {
      app = "coin-master-api"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "coin-master-api"
      }
    }

    template {
      metadata {
        name = "coin-master-api"

        labels = {
          app = "coin-master-api"

          run = "coin-master-api"
        }
      }

      spec {
        container {
          name  = "coin-master-api"
          image = "guyseaneden/coin-master-api"

          port {
            container_port = 8000
          }

          env {
            name = "EXCHANGE_API_KEY"

            value_from {
              secret_key_ref {
                name = "api-key"
                key  = "exchange_api_key"
              }
            }
          }

          env {
            name  = "EXCHANGE_BASE_URL"
            value = "https://v6.exchangerate-api.com"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "coin_master_api_internal_service" {
  metadata {
    name = "coin-master-api-internal-service"

    labels = {
      run = "coin-master-api-internal-service"
    }
  }

  spec {
    port {
      protocol    = "TCP"
      port        = 80
      target_port = "8000"
    }

    selector = {
      app = "coin-master-api"
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_ingress" "coin_master_api_ingress" {
  metadata {
    name = "coin-master-api-ingress"
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = "coin-master-api.com"

      http {
        path {
          path = "/"

          backend {
            service_name = "coin-master-api-internal-service"
            service_port = "80"
          }
        }
      }
    }
  }
}
```

Verify you got no errors, and append the output to your tf file.

_Optional: You can configure dependant object to reference each other's properties to prevent hard coding names.
check the TF file in this repo to see examples._

### Step 4 - Deploying with Terraform

See what needs to be deployed to match the tf file you've created:
```
terraform plan
```
Examine the changes and make sure you'd like to create the resources.
Then deploy, running:
```
terraform apply
```

Expected output:
```
kubernetes_secret.api_key: Creating...
kubernetes_deployment.coin_master_deployment: Creating...
kubernetes_secret.api_key: Creation complete after 0s [id=default/api-key]
kubernetes_deployment.coin_master_deployment: Still creating... [10s elapsed]
kubernetes_deployment.coin_master_deployment: Still creating... [20s elapsed]
kubernetes_deployment.coin_master_deployment: Still creating... [30s elapsed]
kubernetes_deployment.coin_master_deployment: Still creating... [40s elapsed]
kubernetes_deployment.coin_master_deployment: Still creating... [50s elapsed]
kubernetes_deployment.coin_master_deployment: Still creating... [1m0s elapsed]
kubernetes_deployment.coin_master_deployment: Still creating... [1m10s elapsed]
kubernetes_deployment.coin_master_deployment: Still creating... [1m20s elapsed]
kubernetes_deployment.coin_master_deployment: Still creating... [1m30s elapsed]
kubernetes_deployment.coin_master_deployment: Creation complete after 1m31s [id=default/coin-master-deployment]
kubernetes_service.coin_master_api_internal_service: Creating...
kubernetes_service.coin_master_api_internal_service: Creation complete after 0s [id=default/coin-master-api-internal-service]
kubernetes_ingress.coin_master_api_ingress: Creating...
kubernetes_ingress.coin_master_api_ingress: Creation complete after 0s [id=default/coin-master-api-ingress]

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
```

Browse to the address _http://coin-master-api.com/rate/USD/ILS_ (or just curl it).
Note that for the first few minutes you might get a 503 Error, Just wait for the service to finish loading and refresh the page.

Expected output:
```json
{"rate":3.2071}
```

For Debugging errors, these are the commands that helped me:
```
# logs from the pod
kubectl logs coin-master-deployment-XXXXXXXXX-XXXXX

# logs from the ingress
kubectl logs pod/ingress-nginx-controller-XXXXXXXXX-XXXXX -n ingress-nginx

# Observe details about resources
kubectl describe <resource-type> <resource-name> -n <resource-namesapce>
```