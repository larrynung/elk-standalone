#update system
sudo setenforce 0
sudo yum update -y
sudo yum -y install java-1.8.0-openjdk jq wget unzip

#increase limits
echo "
elasticsearch soft nofile 65536
elasticsearch hard nofile 65536
elasticsearch soft memlock unlimited
elasticsearch hard memlock unlimited" | sudo tee -a /etc/security/limits.conf

#download elasticsearch
wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-6.2.3.rpm

#install elasticsearch
sudo rpm -i elasticsearch-6.2.3.rpm
sudo systemctl enable elasticsearch.service

#update listening host
echo "network.host: 0.0.0.0" | sudo tee -a /etc/elasticsearch/elasticsearch.yml

#start elasticsearch
sudo systemctl start elasticsearch.service


#setup Kibana.repo
echo "[kibana-6.x]
name=Kibana repository for 6.x packages
baseurl=https://artifacts.elastic.co/packages/6.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md" | sudo tee /etc/yum.repos.d/Kibana.repo

#install Kibana
sudo yum -y install kibana
sudo chkconfig --add kibana
sudo /sbin/chkconfig kibana on
echo 'server.host: 0.0.0.0' | sudo tee -a /etc/kibana/kibana.yml
sudo service kibana restart

#port forwording for Kibana, so you can access via port 80
sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 5601
sudo iptables -t nat -I OUTPUT -p tcp -d 127.0.0.1 --dport 80 -j REDIRECT --to-ports 5601

#remove the old format kibana index
curl -XDELETE http://localhost:9200/.kibana


#setup logStash.repo
echo "[logstash-6.x]
name=Elastic repository for 6.x packages
baseurl=https://artifacts.elastic.co/packages/6.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md" | sudo tee /etc/yum.repos.d/logStash.repo

#install logStash
sudo yum install -y logstash
sudo /sbin/chkconfig logstash on

#setup logStash to handle syslog
echo 'input {
  beats {
    port => 5044
    ssl => false
  }
}
' | sudo tee /etc/logstash/conf.d/02-beats-input.conf

echo 'filter {
  if [type] == "syslog" {
    grok {
      match => { "message" => "%{SYSLOGTIMESTAMP:syslog_timestamp} %{SYSLOGHOST:syslog_hostname} %{DATA:syslog_program}(?:\[%{POSINT:syslog_pid}\])?: %{GREEDYDATA:syslog_message}" }
      add_field => [ "received_at", "%{@timestamp}" ]
      add_field => [ "received_from", "%{host}" ]
    }
    syslog_pri { }
    date {
      match => [ "syslog_timestamp", "MMM  d HH:mm:ss", "MMM dd HH:mm:ss" ]
    }
  }
}
' | sudo tee /etc/logstash/conf.d/10-syslog-filter.conf

echo 'output {
  elasticsearch {
    hosts => ["localhost:9200"]
    sniffing => true
    manage_template => false
    index => "%{[@metadata][beat]}-%{+YYYY.MM.dd}"
    document_type => "%{[@metadata][type]}"
  }
}
' | sudo tee /etc/logstash/conf.d/30-elasticsearch-output.conf

sudo service logstash restart


#Install filebeat client (as forwarder)
echo '[beats]
name=Elastic Beats Repository
baseurl=https://packages.elastic.co/beats/yum/el/$basearch
enabled=1
gpgkey=https://packages.elastic.co/GPG-KEY-elasticsearch
gpgcheck=1' | sudo tee /etc/yum.repos.d/filebeat.repo
sudo yum install -y filebeat

##
echo 
sudo vi /etc/filebeat/filebeat.yml

[root@client1 ~]# systemctl restart filebeat
[root@client1 ~]# systemctl enable filebeat


