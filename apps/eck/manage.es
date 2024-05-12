// curl -XPUT "https://elasticsearch.anyflow.net/_security/user/anyflow" -u elastic:1mp764023XwjL4MBPvCK0jf3 -H 'Content-Type: application/json' -d'
// {
//   "password" : "mycluster",
//   "roles" : ["superuser"]
// }'

// curl -X PUT "https://anyflow:mycluster@elasticsearch.anyflow.net/_cluster/settings" -u anyflow:mycluster -H 'Content-Type: application/json' -d '{
//   "persistent": {
//     "action.destructive_requires_name": false
//   }
// }'

// curl -X DELETE "elasticsearch-es-http.cluster:9200/otel-cluster*" -u anyflow:mycluster

PUT /_cluster/settings
{ "persistent": { "action.destructive_requires_name": false } }
GET /dockebi-*/_search?size=100

GET /istio-access-log-*/_search?size=100
