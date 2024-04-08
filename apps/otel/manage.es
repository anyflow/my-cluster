// curl -X PUT "https://anyflow:mycluster@loki.anyflow.net/_cluster/settings" -u anyflow:mycluster -H 'Content-Type: application/json' -d '{
//   "persistent": {
//     "action.destructive_requires_name": false
//   }
// }'

// curl -X DELETE "elasticsearch-es-http.cluster:9200/otel-cluster*" -u elastic:aso63i499K40mAqpIS8nc54j

PUT /_cluster/settings
{ "persistent": { "action.destructive_requires_name": false } }
DELETE /otel-cluster-*
GET /dockebi-*
