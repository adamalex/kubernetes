#!/bin/bash

write_scheduler_manifest() {
  cat <<-EOF | sudo tee /etc/kubernetes/manifests/kube-scheduler.manifest > /dev/null
	{
	  "kind": "Pod",
	  "apiVersion": "v1",
	  "metadata": {
	    "name": "kube-scheduler"
	  },
	  "spec": {
	    "hostNetwork": true,
	    "containers": [
	      {
	        "name": "kube-scheduler",
	        "image": "$HYPERKUBE_IMAGE",
	        "command": [
	          "/hyperkube",
	          "scheduler",
	          "--master=$MY_IP:8080"
	        ],
	        "livenessProbe": {
	          "httpGet": {
	            "host" : "127.0.0.1",
	            "path": "/healthz",
	            "port": 10251
	          },
	          "initialDelaySeconds": 15,
	          "timeoutSeconds": 15
	        }
	      }
	    ]
	  }
	}
	EOF
}
