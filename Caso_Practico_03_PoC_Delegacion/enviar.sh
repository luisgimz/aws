#!/bin/bash

# ----------- VARIABLES DEFINIDAS -----------
BUCKET="nexora-poc-luis"
SEDE="sede-cadiz"
FECHA=$(date +%F)
ANYO=$(date +%Y)
MES=$(date +%m)
DIA=$(date +%d)

SALIDA="$HOME/fitosanitario/salida"
GUARDADOS="$HOME/fitosanitario/guardados"
DESCARGAS="$HOME/fitosanitario/descargas"
LOGS="$HOME/fitosanitario/logs"

LOG_SUBIDA="$LOGS/subida_$FECHA.log"
LOG_DESCARGA="$LOGS/descarga_$FECHA.log"

# ---------- CREAR ESTRUCTURA DE DIRECTORIOS -----------
mkdir -p "$SALIDA" "$GUARDADOS" "$DESCARGAS" "$LOGS"

# ----------- SUBIDA Y VERIFICACIÓN -----------
echo "=== Subida $(date '+%F %T') ===" | tee -a "$LOG_SUBIDA"

for fichero in "$SALIDA"/*; do
    [ -e "$fichero" ] || continue          # Si no hay ficheros, pasa
    nombre=$(basename "$fichero")
    clave="$SEDE/$ANYO/$MES/$DIA/$nombre"

    # 1. SUBIR A S3
    if ! aws s3 cp "$fichero" "s3://$BUCKET/$clave"; then
        echo "ERROR: no se pudo subir $nombre. Se queda en salida/"
        continue
    fi

    # 2. VERIFICAR INTEGRIDAD POR TAMAÑO
    tam_s3=$(aws s3api head-object --bucket "$BUCKET" --key "$clave" --query ContentLength --output text 2>/dev/null)
    tam_local=$(stat -c %s "$fichero")

    if [ "$tam_s3" != "$tam_local" ]; then
        echo "ERROR: el tamaño no coincide en $nombre (Local: $tam_local B | S3: $tam_s3 B). Se queda en salida/"
        continue
    fi

    # 3. MOVER Y COMPRIMIR LOCALMENTE
    mv "$fichero" "$GUARDADOS/"
    gzip -f "$GUARDADOS/$nombre"
    echo "OK: $nombre subido, verificado y guardado como .gz"

done 2>&1 | tee -a "$LOG_SUBIDA"

# ----------- DESCARGA Y SINCRONIZACIÓN -----------
echo "=== Descarga $(date '+%F %T') ===" | tee -a "$LOG_DESCARGA"

for sede in "$SEDE"; do
    mkdir -p "$DESCARGAS/$sede"
    if aws s3 sync "s3://$BUCKET/$sede/" "$DESCARGAS/$sede/"; then
        echo "OK: $sede actualizada"
    else
        echo "ERROR: no se pudo descargar en $sede"
    fi
done 2>&1 | tee -a "$LOG_DESCARGA"

# ----------- LIMPIEZA AUTOMÁTICA -----------
echo "=== Limpieza $(date '+%F %T') ===" | tee -a "$LOG_SUBIDA"
find "$GUARDADOS" -type f -name "*.gz" -mtime +6 -print -delete | tee -a "$LOG_SUBIDA"