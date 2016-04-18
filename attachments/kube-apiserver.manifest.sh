#!/bin/bash

write_apiserver_manifest() {
  cat <<-EOF | sudo tee /etc/kubernetes/manifests/kube-apiserver.manifest > /dev/null
	{
	  "kind": "Pod",
	  "apiVersion": "v1",
	  "metadata": {
	    "name": "kube-apiserver"
	  },
	  "spec": {
	    "hostNetwork": true,
	    "containers": [
	      {
	        "name": "kube-apiserver",
	        "image": "${HYPERKUBE_IMAGE}",
	        "command": [
	          "/hyperkube",
	          "apiserver",
	          "--token-auth-file=/dev/null",
	          "--insecure-bind-address=0.0.0.0",
	          "--insecure-port=8080",
	          "--advertise-address=$MY_IP",
	          "--service-cluster-ip-range=18.17.0.0/16",
	          "--etcd-servers=http://$MY_IP:2379"
	        ],
	        "ports": [
	          {
	            "name": "https",
	            "hostPort": 443,
	            "containerPort": 443
	          },
	          {
	            "name": "local",
	            "hostPort": 8080,
	            "containerPort": 8080
	          }
	        ],
	        "volumeMounts": [
	          {
	            "name": "srvkube",
	            "mountPath": "/srv/kubernetes",
	            "readOnly": true
	          },
	          {
	            "name": "etcssl",
	            "mountPath": "/etc/ssl",
	            "readOnly": true
	          }
	        ],
	        "livenessProbe": {
	          "httpGet": {
	            "path": "/healthz",
	            "port": 8080
	          },
	          "initialDelaySeconds": 15,
	          "timeoutSeconds": 15
	        }
	      }
	    ],
	    "volumes": [
	      {
	        "name": "srvkube",
	        "hostPath": {
	          "path": "/srv/kubernetes"
	        }
	      },
	      {
	        "name": "etcssl",
	        "hostPath": {
	          "path": "/etc/ssl"
	        }
	      }
	    ]
	  }
	}
	EOF
}
