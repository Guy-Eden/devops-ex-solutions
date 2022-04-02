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


resource "kubernetes_secret" "api_key" {
  metadata {
    name = "api-key"
  }
  data = {
    exchange_api_key = var.api_key
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
    replicas = var.replica_num
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
            value = var.api_url
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
      app = kubernetes_deployment.coin_master_deployment.metadata.0.labels.app
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
          backend {
            service_name = kubernetes_service.coin_master_api_internal_service.metadata.0.name
            service_port = 80
          }
          path = "/"
        }
      }
    }
  }
}