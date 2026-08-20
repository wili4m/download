# vulKiller (vk)

**Autor:** Wiliam de Freitas
**Versão de referência desta documentação:** 1.3.0 (release candidate)
**Estágios do projeto:**

- [Development](https://git.mop.equinix.com.br/wdefreitas/linux/-/tree/main/tools/vulKiller_patcher/development)
- [Release Candidate](https://git.mop.equinix.com.br/wdefreitas/linux/-/tree/main/tools/vulKiller_patcher/release-candidate)
- [Stable](https://git.mop.equinix.com.br/wdefreitas/linux/-/tree/main/tools/vulKiller_patcher/stable)

---

## Visão Geral

**vulKiller (vk)** é uma ferramenta de automação em Bash criada para padronizar e simplificar a instalação de atualizações de segurança (ou atualizações gerais) em servidores Linux, executada via **Vicarius VRX**.

O script:

- Detecta as atualizações disponíveis (somente segurança ou gerais);
- Aplica as atualizações automaticamente;
- Gera relatórios em CSV como evidência, com as versões dos pacotes antes e depois do processo;
- Gerencia exclusões de pacotes (hold list);
- Verifica a necessidade de reboot e pode agendá-lo automaticamente.

---

## Sistemas Operacionais Suportados

| Família | Distribuições |
|---|---|
| Debian-like | Debian, Ubuntu |
| RHEL-like | RHEL, CentOS, Oracle Linux (OL), Rocky Linux |

A detecção do SO é feita automaticamente a partir de `/etc/os-release` (campos `ID` e `VERSION_ID`). Sistemas fora dessa lista fazem o script abortar com erro.

---

## Pré-requisitos

- Privilégios de **root** (o script valida `$EUID` e aborta se não for root);
- Gerenciador de pacotes funcional (`apt` ou `yum`);
- Para **RHEL**: sistema registrado no **Red Hat Subscription Manager** (o script valida isso antes de prosseguir);
- Espaço em disco mínimo disponível (ver tabela de thresholds abaixo).

---

## Funcionalidades Principais

- Atualização automatizada de pacotes (modo geral ou somente segurança);
- Modo de simulação (dry-run), sem aplicar nenhuma mudança real;
- Lista de exclusão de pacotes (hold list), por servidor;
- Geração de relatórios CSV para auditoria (antes/depois);
- Validação de espaço em disco antes de iniciar o processo;
- Correção de *Phased Updates* no Ubuntu (evita falso negativo de pacotes de segurança pendentes);
- Detecção automática de necessidade de reboot (novo kernel instalado);
- Agendamento de reboot com conversão de fuso horário para BRT;
- Suporte multi-distribuição (Debian-like e RHEL-like);
- Log estruturado com trace ID, timestamp e níveis (INFO/WARN/ERROR).

---

## Estrutura de Diretórios e Arquivos

| Caminho | Finalidade |
|---|---|
| `/var/log/vulkiller/vulkiller.log` | Arquivo de log da ferramenta |
| `/var/log/vulkiller/reports/YYYY/MM/DD/` | Relatórios (evidências) gerados em cada execução |
| `/etc/default/equinix/pkgs_hold/` | Diretório de arquivos vazios nomeados como pacotes a serem mantidos em hold |
| `/etc/default/equinix/reboot_schedule/` | Diretório de arquivo vazio nomeado `HHMM` para definir o horário de reboot agendado |
| `/run/vulkiller.lock` | Lock file usado para impedir execuções simultâneas |
| `/etc/apt/apt.conf.d/99-Phased-Updates` | (Ubuntu) Config gerada/validada para desabilitar phased updates |

---

## Uso

```bash
# Executar a atualização (modo padrão, sem confirmação interativa)
./vulKiller-rc.sh

# Simular o processo sem aplicar nenhuma mudança
./vulKiller-rc.sh --simulate

# Exibir a versão da ferramenta
./vulKiller-rc.sh -v | -V | --version

# Exibir ajuda
./vulKiller-rc.sh -h | -H | --help
```

Qualquer parâmetro não reconhecido faz o script exibir a mensagem de ajuda e encerrar.

---

## Variáveis de Configuração (Modais)

| Variável | Valores | Descrição |
|---|---|---|
| `modal_keep_report_files` | `true` / `false` | Mantém (ou remove) os arquivos CSV de relatório após a execução |
| `modal_reboot_after_update` | `true` / `false` | Reinicia automaticamente o servidor quando um novo kernel é instalado. Se `false`, apenas recomenda o reboot manual |
| `modal_update_all_packages` | `true` / `false` | Define se serão aplicadas todas as atualizações disponíveis (`true`) ou somente as de segurança (`false`), respeitando os pacotes em hold |
| `modal_convert_server_time_to_brt` | `true` / `false` | Converte o horário de reboot agendado para o fuso BRT (America/Sao_Paulo) quando o servidor usa um fuso diferente |

### Thresholds de Espaço em Disco (mínimo requerido)

| Ponto de montagem | Mínimo requerido (MB) |
|---|---|
| `/` | 1024 |
| `/boot` | 100 |
| `/boot/efi` | 100 |
| `/var` | 1024 |
| `/usr` | 1024 |
| `/tmp` | 100 |

A verificação só ocorre para os pontos de montagem que existem de fato como partições separadas no host (validado via `df`).

---

## Fluxo de Execução

1. **Validação de execução**: checa privilégio root e adquire lock (`flock`) para impedir instâncias concorrentes.
2. **Parsing de argumentos**: `--simulate`, `-v`/`--version`, `-h`/`--help`, ou execução padrão.
3. **Impressão de informações**: nome, versão, estágio, hostname, SO, versão do SO, uptime.
4. **Validação de espaço em disco** nos pontos de montagem relevantes.
5. **Preparação do repositório**:
   - Ubuntu: garante que phased updates estão desabilitados;
   - Debian/Ubuntu: `apt update`;
   - RHEL-like: valida registro de assinatura (somente RHEL puro).
6. **Geração do relatório de atualizações disponíveis** (`*_updates_available.csv`).
7. **Cálculo do tamanho total das atualizações** e comparação com o espaço em disco disponível em `/usr`.
8. **Processamento da hold list** (`func_pkgs_to_avoid_update`): identifica pacotes a manter e aplica o hold (via `apt-mark hold` ou `--exclude` no yum).
9. **Execução da atualização** (`func_perform_update`): geral ou somente segurança, conforme o modal configurado.
10. **Geração do relatório de evidências** (`*_updates_performed.csv`), com versões antes/depois.
11. **Limpeza dos arquivos temporários** (`func_cleanup`), respeitando `modal_keep_report_files`.
12. **Verificação e, se habilitado, agendamento de reboot** (`func_reboot_server`).
13. **Mensagem final**, com status, horários de início/fim e quantidade de pacotes atualizados.

---

## Relatórios de Evidência (CSV)

### Atualizações disponíveis

**Debian/Ubuntu:**
```
Package;Current Version;Available Version
```

**RHEL-like:**
```
Advisory (Errata);Package
```

### Atualizações realizadas

**Debian/Ubuntu:**
```
Package Name ; Old version ; New version
```

**RHEL-like:**
```
Package old version ; Package new version
```

Os relatórios ficam armazenados em `/var/log/vulkiller/reports/YYYY/MM/DD/`, nomeados com data, trace ID e hostname.

---

## Logging

Formato de cada linha de log:
```
[YYYY-MM-DD HH:MM:SS (TZ)] [traceid] [NÍVEL] mensagem
```

Níveis utilizados: `INFO`, `WARN`, `ERROR` (e `SIMULATION` quando executado com `--simulate`).

Modos de saída do log (`func_log`):

| Modo | Comportamento |
|---|---|
| `both` | Grava no arquivo de log **e** exibe na tela (usado para evidência via VRX) |
| `file` | Grava somente no arquivo de log |
| `screen` | Exibe somente na tela |
| `silent` | Não grava nem exibe |

---

## Política de Reboot

- O reboot só é avaliado se `modal_reboot_after_update=true`.
- A necessidade de reboot é detectada por:
  - **Debian/Ubuntu**: presença de `/var/run/reboot-required` ou comparação do kernel em execução com o kernel instalado mais recente;
  - **RHEL-like**: via `grubby` (quando disponível) ou comparação entre data de instalação do último kernel e data do último boot.
- Se um agendamento válido existir em `/etc/default/equinix/reboot_schedule/` (arquivo único, no formato `HHMM`), o reboot respeita esse horário; caso contrário, é agendado para 5 minutos após a execução.
- **Regras de segurança do agendamento**:
  - Múltiplos arquivos de agendamento → reboot **abortado**;
  - Nome de arquivo fora do formato `HHMM` válido → reboot **abortado**;
  - Em modo `--simulate`, o reboot nunca é executado, apenas relatado.

---

## Funcionalidades de Segurança

| Funcionalidade | Descrição |
|---|---|
| Exigência de privilégio root | Impede execução por usuário não privilegiado |
| Lock de execução única (`flock`) | Evita updates concorrentes e corrupção de estado |
| Modo de simulação (`--simulate`) | Permite validar o processo sem aplicar mudanças |
| Hold list de pacotes | Protege pacotes críticos de atualizações indesejadas |
| Preservação de configurações locais | Uso de `--force-confdef`/`--force-confold` no `apt` |
| Validação de registro RHEL | Impede tentativa de update em sistema não licenciado |
| Correção de Phased Updates (Ubuntu) | Evita falso negativo de patches de segurança pendentes, validado por checksum MD5 do arquivo de config |
| Validação de espaço em disco | Previne falhas/corrupção por disco cheio durante o patching |
| Trilha de auditoria (evidence reports) | CSVs com versões antes/depois para comprovação de compliance |
| Log estruturado com trace ID | Rastreabilidade de cada execução |
| Validação rígida do agendamento de reboot | Aborta em caso de múltiplos agendamentos ou formato inválido |
| Aviso a usuários logados antes do reboot | Broadcast via `shutdown -r`, com tempo para salvar trabalho |
| Validação de tipo de arquivo antes da remoção | Usa `file` para confirmar que é texto antes de `rm -f`, evitando remoção acidental de binários |

---

## Tratamento de Erros e Código de Saída

O script utiliza apenas dois códigos de saída:

| Código | Significado |
|---|---|
| `0` | Execução concluída com sucesso (incluindo simulações e casos sem atualizações pendentes) |
| `1` | Falha em qualquer etapa (privilégio insuficiente, lock ativo, SO não suportado, espaço em disco insuficiente, falha no repositório, falha no agendamento de reboot, etc.) |

Todas as falhas são registradas no log com nível `ERROR` antes do encerramento.

---

## Limitações Conhecidas

- Suporta apenas as distribuições listadas na seção "Sistemas Operacionais Suportados";
- Apenas um agendamento de reboot pode existir por vez em `/etc/default/equinix/reboot_schedule/`;
- O agendamento de reboot depende do `systemd` (`/run/systemd/shutdown/scheduled`) para confirmação.

---

## Histórico de Versões

| Versão | Estágio | Observações |
|---|---|---|
| 1.3.0 | Release Candidate | Versão documentada neste README |

---

## Autor

Wiliam de Freitas <wdefreitas@equinix.com>
