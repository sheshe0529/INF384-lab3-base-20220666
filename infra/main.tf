terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "actual" {}

locals {
  # El entorno academico no permite crear roles IAM. La funcion reutiliza el rol de ejecucion preexistente de la cuenta.
  arn_rol_ejecucion = "arn:aws:iam::${data.aws_caller_identity.actual.account_id}:role/${var.nombre_rol_ejecucion}"

  # El repositorio de imagenes no se declara aca: lo crea el workflow
  # setup-infra, antes de que esta configuracion se aplique por primera vez.
  # La razon es de orden, no de gusto. Una funcion Lambda de tipo imagen
  # exige que la imagen ya exista en el registro, y publicar una imagen no
  # es algo que Terraform sepa hacer.
  #
  # La direccion se arma con el identificador de la cuenta, que es lo unico
  # que cambia entre alumnos. El resto es igual para todos.
  registro        = "${data.aws_caller_identity.actual.account_id}.dkr.ecr.${var.region}.amazonaws.com"
  url_repositorio = "${local.registro}/${var.nombre_aplicacion}"
  imagen_inicial  = "${local.url_repositorio}:${var.tag_inicial}"

  etiquetas = {
    Curso       = "INF384"
    Laboratorio = "3"
    Aplicacion  = var.nombre_aplicacion
  }
}

# Sin esta politica la funcion no puede descargar la imagen.
# El repositorio ya existe: aca solo se le cuelga la politica.
resource "aws_ecr_repository_policy" "descarga_lambda" {
  repository = var.nombre_aplicacion

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PermitirDescargaDesdeLambda"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
        ]
      },
    ]
  })
}

# El nombre del grupo debe coincidir con el que Lambda usa por convencion,
# o la funcion crea el suyo y esta retencion no aplica.
resource "aws_cloudwatch_log_group" "funcion" {
  name              = "/aws/lambda/${var.nombre_aplicacion}"
  retention_in_days = 1

  tags = local.etiquetas
}

resource "aws_lambda_function" "app" {
  function_name = var.nombre_aplicacion
  role          = local.arn_rol_ejecucion
  package_type  = "Image"
  image_uri     = local.imagen_inicial
  architectures = ["x86_64"]
  memory_size   = 512
  timeout       = 30

  environment {
    variables = {
      APP_VERSION = var.version_aplicacion
    }
  }

  # La imagen es propiedad del pipeline de aplicacion. Sin esta linea, la
  # siguiente ejecucion del pipeline de infraestructura revierte el
  # despliegue al tag inicial.
  lifecycle {
    ignore_changes = [image_uri]
  }

  depends_on = [
    aws_cloudwatch_log_group.funcion,
    aws_ecr_repository_policy.descarga_lambda,
  ]

  tags = local.etiquetas
}
