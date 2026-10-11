module "registry" {
  source = "../../modules/registry"

  name = var.name
  # The account is thrown away after the session, so the images can go with it.
  force_delete = true
}
