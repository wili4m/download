
## health_check_swap

Identifica se o uso de **SWAP** está dentro de limites aceitáveis determinados na variável `swap_threshold`.

| Por padrão, o threshold é 79.99% de SWAP em uso.

Caso o uso esteja acima do threshold, realiza verificações e move os caches da SWAP para a RAM.

[health_check_swap.sh](usr/local/sbin/equinix/health_check_swap/)