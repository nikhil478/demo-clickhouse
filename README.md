# demo-clickhouse

/* From Observability at Scale with ClickStack: October 14, 2025 */

-- getting started  --

docker run -p 8080:8080 -p 4317:4317 -p 4318:4318 docker.hyperdx.io/hyperdx/hyperdx-all-in-one


curl -O https://storage.googleapis.com/hyperdx/sample.tar.gz

export CLICKSTACK_API_KEY=<YOUR_INGESTION_API_KEY>


for filename in $(tar -tf sample.tar.gz); do
  endpoint="http://localhost:4318/v1/${filename%.json}"
  echo "loading ${filename%.json}"
  tar -xOf sample.tar.gz "$filename" | while read -r line; do
    printf '%s\n' "$line" | curl -s -o /dev/null -X POST "$endpoint" \
    -H "Content-Type: application/json" \
    -H "authorization: ${CLICKSTACK_API_KEY}" \
    --data-binary @-
  done
done

Data ingestion 

docker run --rm -it \
  -v "$PWD/my-config.yaml:/etc/otelcol-config.yaml:ro" \
  --name otel-agent \
  otel/opentelemetry-collector-contrib:latest \
  --config /etc/otelcol-config.yaml