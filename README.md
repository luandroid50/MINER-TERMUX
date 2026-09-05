# Verus Termux Miner — VIPOR.NET (SA)

Instalador para transformar um celular Android + Termux em um nó de mineração de
VerusCoin (VRSC), usando o minerador pré-compilado de
[`Darktron/pre-compiled`](https://github.com/Darktron/pre-compiled) (branch `generic`,
compatível apenas com **ARMv8 / aarch64 64-bit** — confirmado no README oficial do
repositório).

---

## 1. Instalação

1. Copie `install.sh` para o celular (via `git`, `curl`, transferência de arquivo, etc).
2. No Termux:

```bash
wget -O install.sh https://raw.githubusercontent.com/luandroid50/MINER-TERMUX/main/install.sh
chmod +x install.sh
./install.sh
```

3. O script é **idempotente**: pode ser executado quantas vezes quiser. Ele não vai
   duplicar dependências, não vai baixar o CCminer de novo se já estiver funcional, e
   não vai resetar a senha do SSH se ela já tiver sido definida antes.

Ao final, ele mostra um resumo com pool, worker, carteira (mascarada), status do SSH e
como acessar o console do minerador.

### Alterar carteira, pool ou senha depois

Edite o arquivo:

```text
~/CCMINER/config.conf
```

e rode `./install.sh` novamente para aplicar as mudanças (ele regenera a configuração
real do CCminer a partir desse arquivo).

---

## 2. Acesso via SSH

O script configura o servidor SSH do Termux e define a senha `9292` (apenas na
primeira execução — trocas manuais feitas depois com `passwd` são preservadas).

Ao final da instalação (ou rodando `./install.sh --status`), você verá algo como:

```text
ssh <usuario>@<IP-local> -p <porta>
```

- **Usuário**: o mesmo do Termux (`whoami`), normalmente algo como `u0_a123`.
- **Porta**: detectada automaticamente a partir de `sshd_config`; no Termux padrão é `8022`.
- **IP local**: detectado via `ip route`, válido apenas dentro da mesma rede Wi-Fi.

Recomendação de segurança: troque a senha padrão assim que possível com `passwd`
dentro do próprio Termux.

---

## 3. Ver o console do minerador (hashrate, shares, erros)

O CCminer roda dentro de uma sessão `tmux` chamada `ccminer`, o que permite fechar o
SSH ou o app do Termux sem parar a mineração.

```bash
tmux attach -t ccminer
```

Você verá o console ao vivo: hashrate, shares aceitas/rejeitadas, dificuldade e
mensagens do Stratum/pool.

**Para sair sem parar o minerador:**

```text
CTRL + B, depois D
```

(isso "desanexa" da sessão tmux — o CCminer continua rodando em segundo plano)

---

## 4. Parar / reiniciar o minerador

**Parar:**

```bash
tmux kill-session -t ccminer
```

**Reiniciar:**

```bash
~/CCMINER/start-miner.sh
```

(esse script verifica se já existe um processo rodando antes de iniciar outro, então
é seguro chamá-lo várias vezes)

**Parar tudo, inclusive o SSH:**

```bash
tmux kill-session -t ccminer
pkill sshd
```

---

## 5. Verificação e diagnóstico

```bash
./install.sh --status        # mostra o estado atual, sem alterar nada
./install.sh --diagnostico   # roda os testes de verificação (arquitetura, CCminer,
                              # SSH, tmux, conectividade com a pool), sem reinstalar
```

Todos os eventos importantes ficam registrados em `~/verus-install.log`.

---

## 6. Limitações reais do Termux/Android (sem root)

Para manter o instalador honesto, aqui estão as partes do pedido original que **não
são totalmente possíveis** sem root, e o que foi feito no lugar:

### 6.1. "Iniciar automaticamente quando o Termux for aberto"

✅ **Resolvido de forma real**: foi adicionado um gancho em `~/.bashrc` que verifica e
inicia o SSH e o CCminer toda vez que uma **nova sessão interativa do Termux é
aberta** (nova aba/sessão do app).

❌ **Não incluído**: iniciar automaticamente **no boot do Android**, sem o app Termux
ser aberto manualmente. Isso exigiria o app separado **Termux:Boot**
(`com.termux.boot`), que:

- precisa ser instalado à parte (não vem com o Termux principal);
- depende do Android permitir a execução do `BroadcastReceiver` no boot, algo que
  fabricantes como a **Samsung** (relevante pois os aparelhos em uso são Galaxy S10)
  costumam restringir agressivamente via otimização de bateria/gerenciamento de apps
  em segundo plano;
- não tem garantia de funcionamento consistente sem ajustes manuais (desativar
  otimização de bateria para o Termux e o Termux:Boot, permitir "auto-start" nas
  configurações da Samsung, etc).

Por isso essa parte foi deixada de fora do script principal — se quiser, posso te
ajudar a configurar o Termux:Boot manualmente como um passo opcional adicional.

### 6.2. Temperatura da CPU

❌ Não incluído no `--status`. Sem root e sem o app **Termux:API**
(`termux-battery-status`), não há forma confiável de ler a temperatura da CPU a
partir do Termux puro. O campo aparece no status como "indisponível".

### 6.3. API de monitoramento do CCminer (hashrate via rede)

A `config.json` gerada habilita a API do CCminer (`api-bind`), mas **restrita a
`127.0.0.1`** (somente local), diferente do padrão do repositório original que expõe
em `0.0.0.0`. Isso foi uma escolha deliberada de segurança: evita que qualquer
dispositivo na rede local consulte/controle o minerador sem necessidade. O consumo
dessa API não foi automatizado no `--status` porque não foi possível testar
previamente, no ambiente onde este script foi escrito, o protocolo exato de resposta
dessa API específica deste binário — em vez de inventar um parser que poderia
simplesmente falhar silenciosamente, preferi manter o `--status` baseado em checagem
de processo (`pgrep`) e sessão `tmux`, que são 100% confiáveis.

---

## 7. Arquivos gerados

```text
~/CCMINER/
├── ccminer                 # binário baixado do repositório
├── ccminer-config.json     # configuração real usada pelo CCminer (regenerada a cada execução)
├── config.conf             # configuração central editável (carteira, pool, senha)
├── start-miner.sh          # inicia o minerador de forma segura (sem duplicar)
└── .ssh_password_set       # marcador interno (não editar)

~/verus-install.log         # log de instalação e diagnóstico
```
