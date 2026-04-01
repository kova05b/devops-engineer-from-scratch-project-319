resource "yandex_vpc_network" "main" {
  name      = "${local.name_prefix}-net"
  folder_id = var.yc_folder_id
  labels    = local.labels
}

resource "yandex_vpc_gateway" "nat" {
  name = "${local.name_prefix}-nat-gw"
  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "nat" {
  name       = "${local.name_prefix}-rt"
  network_id = yandex_vpc_network.main.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat.id
  }
}

resource "yandex_vpc_subnet" "main" {
  name           = "${local.name_prefix}-subnet"
  zone           = var.yc_zone
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [var.network_cidr]
  route_table_id = yandex_vpc_route_table.nat.id
  labels         = local.labels
}

# Security group для Managed Kubernetes (ноды и служебный трафик).
# Правила намеренно простые — под учебный проект. Потом можно ужесточить.
resource "yandex_vpc_security_group" "k8s" {
  name       = "${local.name_prefix}-k8s-sg"
  network_id = yandex_vpc_network.main.id
  labels     = local.labels

  # Без этого NLB помечает цели UNHEALTHY (пробы не с 0.0.0.0/0).
  # https://yandex.cloud/en/docs/managed-kubernetes/operations/connect/security-groups
  ingress {
    description       = "Network Load Balancer health checks"
    protocol          = "TCP"
    from_port         = 0
    to_port           = 65535
    predefined_target = "loadbalancer_healthchecks"
  }

  # Чтобы kubectl (external endpoint) работал, нужно открыть TCP/443 на security group master API.
  ingress {
    protocol       = "TCP"
    description    = "Kubernetes API (kubectl) - HTTPS"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  # SSH к нодам (если понадобится дебаг). Можно удалить/закрыть позже.
  ingress {
    protocol       = "TCP"
    description    = "SSH"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  # HTTP с интернета на LoadBalancer (443 уже открыт правилом Kubernetes API выше).
  ingress {
    protocol       = "TCP"
    description    = "HTTP public (LoadBalancer)"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  # K8s NodePort range (по умолчанию).
  ingress {
    protocol       = "TCP"
    description    = "Kubernetes NodePort"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 30000
    to_port        = 32767
  }

  # Внутрикластерный трафик.
  ingress {
    protocol          = "ANY"
    description       = "Intra SG"
    predefined_target = "self_security_group"
  }

  egress {
    protocol       = "ANY"
    description    = "Outbound"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security group для PostgreSQL — разрешаем доступ только с k8s SG.
resource "yandex_vpc_security_group" "postgres" {
  name       = "${local.name_prefix}-pg-sg"
  network_id = yandex_vpc_network.main.id
  labels     = local.labels

  ingress {
    protocol          = "TCP"
    description       = "PostgreSQL from k8s"
    port              = 5432
    security_group_id = yandex_vpc_security_group.k8s.id
  }

  # На практике иногда SG-to-SG правила с Managed Service работают не так,
  # как ожидается. Чтобы задание гарантированно проверялось,
  # дополнительно разрешаем доступ из CIDR подсети, где живут ноды k8s.
  ingress {
    protocol       = "TCP"
    description    = "PostgreSQL from k8s subnet CIDR"
    port           = 5432
    v4_cidr_blocks = [var.network_cidr]
  }

  ingress {
    protocol       = "TCP"
    description    = "PostgreSQL from Kubernetes pod CIDR (overlay)"
    port           = 5432
    v4_cidr_blocks = [var.k8s_pod_cidr]
  }

  # Пул соединений Odyssey (часто порт 6432); без правила nc/psql на 6432 даёт FAIL при открытом 5432.
  ingress {
    protocol          = "TCP"
    description       = "Odyssey pooler from k8s"
    port              = 6432
    security_group_id = yandex_vpc_security_group.k8s.id
  }

  ingress {
    protocol       = "TCP"
    description    = "Odyssey pooler from k8s subnet CIDR"
    port           = 6432
    v4_cidr_blocks = [var.network_cidr]
  }

  ingress {
    protocol       = "TCP"
    description    = "Odyssey pooler from Kubernetes pod CIDR"
    port           = 6432
    v4_cidr_blocks = [var.k8s_pod_cidr]
  }

  dynamic "ingress" {
    for_each = var.postgres_allow_anywhere_ingress ? [5432, 6432] : []
    content {
      protocol       = "TCP"
      description    = "DEV: Postgres/Odyssey port ${ingress.value} from anywhere (отключи в проде)"
      port           = ingress.value
      v4_cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    protocol       = "ANY"
    description    = "Outbound"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

