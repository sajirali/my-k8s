## PART 1
# In base/shared EKS module
# (relies on a python script to get the cluster CA thumbprint)

data "external" "cluster-cert-thumbprint" {
  program = ["runway", "run-python", "get_idp_root_cert_thumbprint.py"]

  query = {
    url = "${aws_eks_cluster.cluster.identity.0.oidc.0.issuer}"
  }
}
resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = ["${data.external.cluster-cert-thumbprint.result.thumbprint}"]
  url = "${aws_eks_cluster.cluster.identity.0.oidc.0.issuer}"
}

resource "aws_ssm_parameter" "oidc_iam_provider_cluster_url" {
  name = "/${local.cluster_name}/oidc-iam-provider-cluster-url"
  type = "String"
  value = "${aws_iam_openid_connect_provider.cluster.url}"
}
resource "aws_ssm_parameter" "oidc_iam_provider_cluster_arn" {
  name = "/${local.cluster_name}/oidc-iam-provider-cluster-arn"
  type = "String"
  value = "${aws_iam_openid_connect_provider.cluster.arn}"
}


## PART 2
# Example creating a role using the iam provider and associating a container with it

data "aws_ssm_parameter" "oidc_iam_provider_cluster_url" {
  name = "/${local.cluster_name}/oidc-iam-provider-cluster-url"
}
data "aws_ssm_parameter" "oidc_iam_provider_cluster_arn" {
  name = "/${local.cluster_name}/oidc-iam-provider-cluster-arn"
}

resource "aws_s3_bucket" "bucket" {
  bucket_prefix = "eks-${local.job_name}-"
  acl = "private"
  force_destroy = "true"
}

data "aws_iam_policy_document" "service_account_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect = "Allow"

    condition {
      test = "StringEquals"
      variable = "${replace(data.aws_ssm_parameter.oidc_iam_provider_cluster_url.value, "https://", "")}:sub"
      values = ["system:serviceaccount:default:${local.sa_name}"]
    }

    principals {
      identifiers = ["${data.aws_ssm_parameter.oidc_iam_provider_cluster_arn.value}"]
      type = "Federated"
    }
  }
}
resource "aws_iam_role" "service_account" {
  name_prefix = "eks-${local.sa_name}-"
  assume_role_policy = "${data.aws_iam_policy_document.service_account_assume_role_policy.json}"
}
data "aws_iam_policy_document" "service_account" {

  statement {
    actions = [
      "s3:ListBucket",
      "s3:ListBucketVersions"
    ]
    resources = ["${aws_s3_bucket.bucket.arn}"]
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject*"
    ]
    resources = ["${aws_s3_bucket.bucket.arn}/*"]
  }
}
resource "aws_iam_role_policy" "service_account" {
  role = "${aws_iam_role.service_account.id}"

  policy = "${data.aws_iam_policy_document.service_account.json}"
}

resource "kubernetes_service_account" "service_account" {
  metadata {
    name = "${local.sa_name}"
    annotations = "${
      map(
       "eks.amazonaws.com/role-arn", "${aws_iam_role.service_account.arn}"
      )
    }"
  }
  depends_on = [
    "aws_iam_role_policy.service_account",
  ]
}

resource "kubernetes_job" "job" {
  metadata {
    name = "${local.job_name}"
  }
  spec {
    template {
      metadata {}
      spec {
        service_account_name = "${kubernetes_service_account.service_account.metadata.0.name}"
        container {
          name    = "main"
          image   = "amazonlinux:2018.03"
          command = [
            "sh",
            "-c",
            "curl -sL -o /s3-echoer https://github.com/mhausenblas/s3-echoer/releases/latest/download/s3-echoer-linux && chmod +x /s3-echoer && echo This is an in-cluster test | /s3-echoer $BUCKET_NAME"
          ]
          env {
            name  = "AWS_DEFAULT_REGION"
            value = "${var.region}"
          }
          env {
            name  = "BUCKET_NAME"
            value = "${aws_s3_bucket.bucket.id}"
          }
          env {
            name  = "ENABLE_IRP"
            value = "true"
          }
          volume_mount {
            mount_path = "/var/run/secrets/kubernetes.io/serviceaccount"
            name = "${kubernetes_service_account.service_account.default_secret_name}"
            read_only = true
          }
        }
        volume {
          name = "${kubernetes_service_account.service_account.default_secret_name}"
          secret {
            secret_name = "${kubernetes_service_account.service_account.default_secret_name}"
          }
        }
        restart_policy = "Never"
      }
    }
  }
}
