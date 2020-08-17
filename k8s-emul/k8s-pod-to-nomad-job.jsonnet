local k8s_namespace = std.extVar("k8s_namespace");
local k8s_pod = std.parseJson(std.extVar("k8s_pod"));
{
  "Job": {
    "ID": k8s_pod.metadata.name,
    "Name": k8s_pod.metadata.name,
    "Type": "service",
    // "Priority": 50,
    "Datacenters": ["dc1"],
    "TaskGroups": [
      {
        "Name": "group1",
        "Count": 1,
        "Tasks": std.map(
          function(k8s_container)
          {
            "Name": k8s_container.name,
            "Driver": "docker",
            "User": "",
            "Config": {
              "image": k8s_container.image,
              "args": k8s_container.args,
              // "network_mode": "container:tests_cluster_1",
              "port_map": std.map(
                function(k8s_port)
                {
                  [k8s_port.name]: k8s_port.containerPort,
                },
                k8s_container.ports
              ),
            },
            "Resources": {
              "CPU": 500,
              "MemoryMB": 2048,
              "Networks": [
                {
                  "Device": "",
                  "CIDR": "",
                  "IP": "",
                  "MBits": 10,
                  "DynamicPorts": [
                  ]
                }
              ]
            },
            "Leader": true
          },
          k8s_pod.spec.containers
        ),
        /*
        "RestartPolicy": {
          "Interval": 300000000000,
          "Attempts": 10,
          "Delay": 25000000000,
          "Mode": "delay"
        },
        "ReschedulePolicy": {
          "Attempts": 10,
          "Delay": 30000000000,
          "DelayFunction": "exponential",
          "Interval": 36000000000000,
          "MaxDelay": 3600000000000,
          "Unlimited": false
        },
        */
        "EphemeralDisk": {
          "SizeMB": 120
        }
      }
    ],
    /*
    "Update": {
      "MaxParallel": 1,
      "MinHealthyTime": 10000000000,
      "HealthyDeadline": 180000000000,
      "AutoRevert": false,
      "Canary": 0
    }
    */
  }
}
