# The cluster created by infra-base/eks, resolved by name.
#
# By data source rather than by remote state, which is how every other root
# here finds the one before it: eks finds the VPC by tag, and reading another
# root's state would couple this one to where that state is kept as well as to
# what it contains.
data "aws_eks_cluster" "selected" {
  name = local.cluster_name
}

# A short-lived token for the Helm provider below.
#
# aws_eks_cluster_auth rather than an exec plugin: the token is produced during
# the plan, by the same credentials Terraform is already using, so there is no
# second authentication path to configure and nothing for a CI runner to have
# installed. It expires in 15 minutes, which outlives any single apply.
data "aws_eks_cluster_auth" "selected" {
  name = local.cluster_name
}
