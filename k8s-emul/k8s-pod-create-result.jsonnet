local ext_json = function(n) std.parseJson(std.extVar(n));
local k8s_namespace = std.extVar("k8s_namespace");
local k8s_pod = ext_json("k8s_pod");
local nomad_job_result = ext_json("nomad_job_result");
{
  kind: "Pod",
  apiVersion: "v1",
  metadata: {
    name: k8s_pod.metadata.name,
    namespace: k8s_namespace,
    selfLink: "/api/v1/namespaces/%s/pods/%s" % [k8s_namespace, k8s_pod.metadata.name],
    // uid: 6d132155-ac89-4a76-809f-5db50e290146
  },
  status: {
    phase: "Pending",
    // qosClass: "Burstable",
  }
}
