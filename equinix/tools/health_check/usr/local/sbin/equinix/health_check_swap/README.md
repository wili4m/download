
## health_check_swap

Determina se o uso de **SWAP** está dentro de limites aceitáveis determinados na variável `swap_threshold`. Por padrão, o threshold é 79.99% de SWAP em uso.

Caso o uso de SWAP exceda o threshold, o script verifica se há memória suficiente para mover o cache da SWAP para a RAM. Se houver, a SWAP é **desativada momentaneamente**, o que força a migração dos dados em cache da SWAP para a RAM.

Caso não haja RAM suficiente para mover o cache, o script, por padrão, apenas registra a seguinte mensagem de erro no log do sistema:

```Insufficient available memory (${mem_free}MB) to move caches from SWAP to RAM. Current SWAP usage is at ${swap_percent}% (${swap_used}MB).```

Toda operação é regirada no log do sistema:

* Debian e Debian-Like: `/var/log/syslog`
* RHEL e RHEL-Like: `/var/log/messages`

## Logs

Esses são os logs do código:

#### O código foi inicializado e vai checar o cenário:
```
Checking SWAP usage...
```

#### Foi Identificado uso de SWAP acima do threshold e memória livre o suficiente para mover os caches:
```
SWAP usage is at 90.24% (999MB), which exceeds the threshold of 79.99%. Initiating move of caches from SWAP to RAM.
```

#### Foi Identificado uso de SWAP acima do threshold, mas não há memória livre o suficiente para mover os caches:
```
Insufficient available memory (200MB) to move caches from SWAP to RAM. Current SWAP usage is at 90.24}% (999MB).
```

#### O cache da SWAP foi movido para a memória RAM.
```
 Moved caches from SWAP to Memory.
```

#### Ouve uma falha na operação ou a SWAP não pôde ser reativada:
```
Failed to move caches from SWAP to RAM or SWAP could not be re-enabled.
```

## Deploy

São necessários 4 passos para disponibilizar o código no servidor:

1. Criar o script o diretório /usr/local/sbin/equinix/health_check_swap.sh
```mkdir -p /usr/local/sbin/equinix/```

2. Disponibilizar o código em `/usr/local/sbin/equinix/health_check_swap.sh`

3. Aplicar permissão de execução no arquivo:
```chmod +x /usr/local/sbin/equinix/health_check_swap.sh```

4. Criar o Cronjob [/etc/cron.d/health_check_swap](../../../../../etc/cron.d/health_check_swap/).