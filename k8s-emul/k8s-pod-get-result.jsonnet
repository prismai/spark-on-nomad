local ext_json = function(n) std.parseJson(std.extVar(n));
local k8s_namespace = std.extVar("k8s_namespace");
local nomad_job = ext_json("nomad_job");
{
  kind: "Pod",
  apiVersion: "v1",
  metadata: {
    name: nomad_job.Name,
    namespace: k8s_namespace,
    uid: nomad_job.ID,
    // selfLink: "/api/v1/namespaces/%s/pods/%s" % [k8s_namespace, k8s_pod.metadata.name],
    // uid: 6d132155-ac89-4a76-809f-5db50e290146
  },
  // status: {
  //   phase: "Pending",
  //   // qosClass: "Burstable",
  // }
}
