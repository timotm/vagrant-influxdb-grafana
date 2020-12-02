## Run grafana + influx in a ubuntu VM

Assumes vagrant and virtualbox

To start, simply run
`vagrant up`

InfluxDB is listening at http://monitoring.local:8086 and is pre-configured with a bucket `monitoring` under organization `home`. A token with write permissions to that bucket is generated to `/home/vagrant/influx-write-token.txt`. 

Grafana's WebUI is served at https://monitoring.local:3000, with default credentials `admin`/`admin`.

