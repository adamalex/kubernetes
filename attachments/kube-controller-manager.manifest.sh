#!/bin/bash

write_controller_manifest() {
  cat <<-EOF | sudo tee /etc/kubernetes/manifests/kube-controller-manager.manifest > /dev/null
	{
	  "kind": "Pod",
	  "apiVersion": "v1",
	  "metadata": {
	    "name": "kube-controller-manager"
	  },
	  "spec": {
	    "hostNetwork": true,
	    "containers": [
	      {
	        "name": "kube-controller-manager",
	        "image": "$HYPERKUBE_IMAGE",
	        "command": [
	          "/hyperkube",
	          "controller-manager",
	          "--master=$MY_IP:8080"
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
	            "host": "127.0.0.1",
	            "path": "/healthz",
	            "port": 10252
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
