provider "aws"{
    region = "us-east-1"
}

provider "vault"{
  address = "http://44.223.17.255:8200"
  skip_child_token = true

  auth_login {
    path = "auth/approle/login"

    parameters = {
      role_id = "32c68d6a-a1c1-120e-2fc4-fb9b7681f940"
      secret_id = "0f74bd54-802d-7688-8d3a-bf96ae0b7160"
    }
  }
}

data "vault_kv_secret_v2" "example" {
  mount = "kv" // change it according to your mount
  name  = "test-secret" // change it according to your secret
}

resource "aws_instance" "example" {
  ami           = "ami-053b0d53c279acc90"
  instance_type = "t2.micro"

  tags = {
    Name = "test"
    Secret = data.vault_kv_secret_v2.example.data["username"]
  }
}