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
    token                  = data.aws_eks_cluster_auth.selected.token
  }
}
