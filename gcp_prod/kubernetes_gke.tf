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

variable "config_path"{
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

  config_path = var.config_path
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

resource "kubernetes_deployment" "coin_app" {
  metadata {
    annotations = {}
    name = "coin-app"
    labels = {
      run = "coin-app"
    }
  }
  spec {
    replicas = var.replica_num
    selector {
      match_labels = {
        run = "coin-app"
      }
    }
    template {
      metadata {
        annotations = {}
        labels = {
          run = "coin-app"
        }
      }
      spec {
        node_selector = {}
        automount_service_account_token = false 
        enable_service_links = false
        container {
          args = []
          command = []
          name  = "coin-pod"
          image = "guyseaneden/coin-master-api"
          port {
            container_port = 8000
            protocol = "TCP"
          }
          env {
            name = "EXCHANGE_API_KEY"
            value_from {
              secret_key_ref {
                name = "api-key"
                optional = false
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

resource "kubernetes_manifest" "coin_hc_config" {
  manifest = {
    "apiVersion" = "cloud.google.com/v1"
    "kind" = "BackendConfig"
    "metadata" = {
      "name" = "coin-hc-config"
      "namespace" = "default"
    }
    "spec" = {
      "healthCheck" = {
        "checkIntervalSec" = 300
        "port" = 8000
        "type" = "HTTP"
        "requestPath" = "/health"
      }
    }
  }
}

resource "kubernetes_service" "coin_svc" {
  metadata {
    name = "coin-svc"
    labels = {
      run = "coin-svc"
    }
    annotations      = {
              "cloud.google.com/backend-config" = jsonencode({default = "coin-hc-config"})
              "cloud.google.com/neg" = jsonencode({ingress = true})
            }
  }
  spec {
    port {
      protocol    = "TCP"
      name = "http"
      port        = 80
      target_port = "8000"
    }
    selector = {
      run = "coin-app"
    }
    type = "ClusterIP"
  }
}

resource "kubernetes_ingress" "coin_ing" {
  metadata {
    name = "coin-ing"
    annotations = {
      "kubernetes.io/ingress.global-static-ip-name" = "web-static-ip"
    }
  }
  spec {
    backend {
      service_name = "coin-svc"
      service_port = 80
      }
  }
  
}

resource "kubernetes_manifest" "coin_elastic" {
  manifest = {
    "apiVersion" = "elasticsearch.k8s.elastic.co/v1"
    "kind" = "Elasticsearch"
    "metadata" = {
      "name" = "coin-elastic"
      "namespace" = "logging"
    }
    "spec" = {
      "version" = "8.1.3"
      "nodeSets" = [{
        "name" = "default"
        "count" = 1
        "config" = {
          "node.store.allow_mmap" = false
        }
      }]
    }
  }
}

resource "kubernetes_manifest" "coin_kibana" {
  manifest = {
    "apiVersion" = "kibana.k8s.elastic.co/v1"
    "kind" = "Kibana"
    "metadata" = {
      "name" = "coin-kibana"
      "namespace" = "logging"
      "annotations" = {
                  "association.k8s.elastic.co/es-conf" = jsonencode(
                        {
                          authSecretKey  = "default-coin-kibana-kibana-user"
                          authSecretName = "coin-kibana-kibana-user"
                          caCertProvided = true
                          caSecretName   = "coin-kibana-kb-es-ca"
                          url            = "https://coin-elastic-es-http.default.svc:9200"
                          version        = "8.1.3"
                        }
                    )
        }
    }
    "spec" = {
      "version" = "8.1.3"
      "count" = 1
      "elasticsearchRef" = {"name" = "coin-elastic"}
    }
  }
}


resource "kubernetes_manifest" "coin_logging" {
  manifest = {
    "apiVersion" = "logging.banzaicloud.io/v1beta1"
    "kind" = "Logging"
    "metadata" = {
      "name" = "coin-logging-simple"
    }
    "spec"= {
    "fluentd" = {}
    "fluentbit" = {}
    "controlNamespace"="logging"
    }
  }
}


resource "kubernetes_manifest" "coin_logging_output" {
  manifest = {
    "apiVersion" = "logging.banzaicloud.io/v1beta1"
    "kind" = "Output"
    "metadata" = {
      "name" = "coin-logging-output"
      "namespace" = "logging"
    }
    "spec" = {
      "elasticsearch" = {
        "buffer" = {
          "timekey" = "1m"
          "timekey_use_utc" = true
          "timekey_wait" = "30s"
        }
        "host" = "coin-elastic-es-http.logging.svc.cluster.local"
        "password" = {
          "valueFrom" = {
            "secretKeyRef" = {
              "key" = "elastic"
              "name" = "coin-elastic-es-elastic-user"
            }
          }
        }
        "port" = 9200
        "scheme" = "https"
        "ssl_verify" = false
        "ssl_version" = "TLSv1_2"
        "user" = "elastic"
      }
    }
  }
}


resource "kubernetes_manifest" "coin_logging_flow" {
  manifest = {
    "apiVersion" = "logging.banzaicloud.io/v1beta1"
    "kind" = "Flow"
    "metadata" = {
      "name" = "coin-es-flow"
      "namespace" = "logging"
    }
    "spec" = {
      "filters" = [
        {
          "tag_normaliser" = {}
        },
        {
          "parser" = {
            "parse" = {
              "type" = "json"
            }
            "reserve_data" = true
          }
        },
      ]
      "localOutputRefs" = [
        "coin-logging-output",
      ]
      "match" = [
        {
          "select" = {
            "labels" = {
              "app.kubernetes.io/name" = "coin-app"
            }
          }
        },
      ]
    }
  }
}
