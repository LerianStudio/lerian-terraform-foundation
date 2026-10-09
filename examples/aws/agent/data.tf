# The cluster created by infra-base/eks, resolved by name.
#
# By data source rather than by remote state, which is how every other root
# here finds the one before it: eks finds the VPC by tag, and reading another
# root's state would couple this one to where that state is kept as well as to
# what it contains.
data "aws_eks_cluster" "selected" {
  name = local.cluster_name
}
