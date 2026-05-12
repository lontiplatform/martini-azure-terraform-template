resource "tls_private_key" "app_gw" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "app_gw" {
  private_key_pem = tls_private_key.app_gw.private_key_pem

  subject {
    common_name = azurerm_public_ip.app_gw_pip.fqdn
  }

  dns_names = [azurerm_public_ip.app_gw_pip.fqdn]

  validity_period_hours = 8760
  early_renewal_hours   = 720

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "pkcs12_from_pem" "app_gw" {
  password        = random_password.app_gw_pfx.result
  cert_pem        = tls_self_signed_cert.app_gw.cert_pem
  private_key_pem = tls_private_key.app_gw.private_key_pem
}