#!/bin/bash
datename=`date +%Y%m%d-%H%M%S`
server=(121.40.172.23)
ssh $server "source /etc/profile;
	docker pull registry.cn-hangzhou.aliyuncs.com/acme/nginx ;
       	docker stop idatx ;
       	docker rm idatx ;
       	docker run -d --name idatx -p 80:80 -v /home/gitlab-runner/www:/var/www/html registry.cn-hangzhou.aliyuncs.com/boxfish/nginx:latest ;
	scp www/index.html $server:/home/gitlab-runner/www
       	cd /home/gitlab-runner/www ;
	cp index.html index.html.$datename;
	sed -i 's/boxfish/fish/g' index.html"
