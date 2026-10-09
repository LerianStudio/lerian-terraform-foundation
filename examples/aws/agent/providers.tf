provider "aws" {
  region = var.region
}

# The Helm provider talks to the cluster this root just looked up.
#
# No kubeconfig is read. A kubeconfig is a file on whoever's machine runs this,
# pointing at whatever context they last selected — and an apply that installs
# into "the cluster the operator happened to be looking at" is the accident this
# avoids. The endpoint and the CA come from the data source, so the destination
# is the cluster named in the variables and nothing else.
provider "helm" {
  # An attribute, not a block: helm 3.0 moved this to a single object, and the
  # 2.x block form fails to validate.
  kubernetes = {
    host                   = data.aws_eks_cluster.selected.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.selected.certificate_authority[0].data)

    # exec, not the token from aws_eks_cluster_auth. That data source is read
    # during the plan, and an EKS token is good for 15 minutes — so a plan saved
    # for review, queued behind an approval, or re-applied an hour later reaches
    # the cluster holding a credential that has already expired. exec runs when
    # the provider opens the connection, which is during the apply, every time.
    #
    # The cost is a dependency on the AWS CLI being on the machine that applies.
    # That is already true of everything else here: the backend bootstrap, the
    # kubeconfig step and the lerian-cli all shell out to it.
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", var.region]
    }
  }
}
