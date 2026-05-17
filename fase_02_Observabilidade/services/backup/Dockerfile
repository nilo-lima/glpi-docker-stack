# =============================================================================
#  Backup Container — dump agendado do MariaDB + arquivos do GLPI
# =============================================================================
#  Imagem mínima Alpine com:
#    - mariadb-client (mariadb-dump)
#    - tar + gzip (compactação)
#    - tini (init correto, sinaliza filhos)
#    - usuário não-root (UID 1000)
# =============================================================================

FROM alpine:3.20

# Metadados OCI
LABEL org.opencontainers.image.title="GLPI Backup Runner"
LABEL org.opencontainers.image.description="Backup agendado de MariaDB + arquivos GLPI"
LABEL org.opencontainers.image.licenses="MIT"

# --- Pacotes mínimos ---
RUN apk add --no-cache \
        mariadb-client \
        bash \
        tar \
        gzip \
        tzdata \
        tini \
        findutils \
        coreutils \
    && rm -rf /var/cache/apk/*

# --- Usuário não-root ---
# GID 33 = www-data no container GLPI (Debian-based). Criamos um grupo local com
# esse GID (nome glpi-www para evitar conflito com www-data GID 82 do Alpine)
# e adicionamos backup a ele — permite leitura de arquivos como oauth.pem (660, GID 33).
RUN addgroup -g 1000 backup && \
    adduser -D -u 1000 -G backup -s /bin/bash backup && \
    addgroup -g 33 glpi-www && \
    addgroup backup glpi-www

# --- Scripts ---
COPY --chown=backup:backup scripts/ /opt/backup/
RUN chmod +x /opt/backup/*.sh

# --- Diretório de saída ---
RUN mkdir -p /backups && chown backup:backup /backups

USER backup
WORKDIR /opt/backup

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/opt/backup/entrypoint.sh"]
