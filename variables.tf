variable "repo_default_branch" {
  description = "The name of the default repository branch (default: master)"
  default     = "master"
}

variable "repo_name" {
  description = "The name of the CodeCommit repository (e.g. new-repo)."
  default     = "vu-example-repo"
}

variable "www_domain_name" {
  default = "baladigitalcloud-static-site1-vu.baladigitalcloud.com"
}

variable "root_domain_name" {
  default = "baladigitalcloud.com"
}
