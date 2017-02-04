





##       阿里云ECS服务器安装 Gitlab-CI 、Docker Registry 2

## 及runner ,搭建持续集成CI环境，以及实现nginx docker示例

前面知识点介绍部分较长，熟悉的同学可略过，直接跳到下面 “服务器安装” 部分。

* [知识点介绍](#名词解释)


* [gitlab-ci-registry服务器安装](#服务器安装)

  * [通过docker 运行 Gitlab server](#第一部份：通过 docker 启动 gitlab-ci server)
  * [Gitlab HTTPS 的配置](#第二部分：Gitlab https 配置)
  * [配置带用户鉴权功能的 docker registry 2](#第三部分：配置 docker registry 2)

* [简单的 Gitlab-CI 项目构建](#简单的 Gitlab-CI 项目构建)

* [gitlab-ci-multi-runner 的安装](#第五部分： gitlab-ci-multi-runner 的安装)

* [运行CI](#运行CI)

* [集成了私有docker 仓库的配置文件](#集成了私有docker 仓库的配置文件)

* [附录](#附录)

  ###名词解释

先理清一些名词，以及他们之间的关系。

#### 1. Gitlab

GitLab是一个利用Ruby on Rails开发的开源应用程序，实现一个自托管的Git项目仓库，可通过Web界面进行访问公开的或者私人项目。

它拥有与GitHub类似的功能，能够浏览源代码，管理缺陷和注释。可以管理团队对仓库的访问，它非常易于浏览提交过的版本并提供一个文件历史库。团队成员可以利用内置的简单聊天程序（Wall）进行交流。它还提供一个代码片段收集功能可以轻松实现代码复用，便于日后有需要的时候进行查找。

#### 2. Gitlab-CI

 [Gitlab-CI](https://docs.gitlab.com/ce/ci/quick_start/README.html) 是GitLab Continuous Integration（Gitlab持续集成）的简称。 

从Gitlab的8.0版本开始，gitlab就全面集成了Gitlab-CI,并且对所有项目默认开启。

 只要在项目仓库的根目录添加 `.gitlab-ci.yml` 文件，并且配置了Runner（运行器），那么每一次合并请求（MR）或者push都会触发CI [pipeline](https://docs.gitlab.com/ce/ci/pipelines.html) 。 

#### 3. Gitlab-runner

 [Gitlab-runner](https://docs.gitlab.com/ce/ci/runners/README.html) 是 `.gitlab-ci.yml` 脚本的运行器，Gitlab-runner是基于Gitlab-CI的API进行构建的相互隔离的机器（或虚拟机）。

#### 4. Pipelines

 Pipelines是定义于 `.gitlab-ci.yml` 中的不同阶段的不同任务。 

 我把 [Pipelines](https://docs.gitlab.com/ce/ci/pipelines.html) 理解为流水线，流水线包含有多个阶段（ [stages](https://docs.gitlab.com/ce/ci/yaml/README.html#stages) ），每个阶段包含有一个或多个工序（ [jobs](https://docs.gitlab.com/ce/ci/yaml/README.html#jobs) ），比如先购料、组装、测试、包装再上线销售，每一次push或者MR都要经过流水线之后才可以合格出厂。而 `.gitlab-ci.yml` 正是定义了这条流水线有哪些阶段，每个阶段要做什么事。 

------

### 

#### 环境图示：

![](http://oifb0494t.bkt.clouddn.com/16-12-22/9017907-file_1482372367916_a5da.jpg)	





#### Gitlab 组件架构图

![](http://oifb0494t.bkt.clouddn.com/16-12-22/63434672-file_1482370974759_69c2.png)

## 组件

- 前端：Nginx，用于页面及Git tool走http或https协议
- 后端：Gitlab服务，采用Ruby on Rails框架，通过unicorn实现后台服务及多进程
- SSHD：开启sshd服务，用于用户上传ssh key进行版本克隆及上传。注：用户上传的ssh key是保存到git账户中
- 数据库：目前仅支持MySQL和PostgreSQL
- Redis：用于存储用户session和任务，任务包括新建仓库、发送邮件等等
- Sidekiq：Rails框架自带的，订阅redis中的任务并执行


#### GitLab由以下服务构成：

- `nginx`：静态Web服务器
- `gitlab-shell`：用于处理Git命令和修改authorized keys列表
- `gitlab-workhorse`:轻量级的反向代理服务器
- `logrotate`：日志文件管理工具
- `postgresql`   或 `MySQL`：数据库
- `redis`：缓存数据库
- `sidekiq`：用于在后台执行队列任务（异步执行）
- `unicorn`：An HTTP server for Rack applications，GitLab Rails应用是托管在这个服务器上面的。

> > 重点讲一下gitlab-shell和gitlab-workhorse。
> >
> > ##### Gitlab Shell
> >
> > GitLab Shell有两个作用：为GitLab处理Git命令、修改authorized keys列表。
> >
> > 当通过SSH访问GitLab Server时，GitLab Shell会：
> >
> > 1. 限制执行预定义好的Git命令（git push, git pull, git annex）
> > 2. 调用GitLab Rails API 检查权限
> > 3. 执行pre-receive钩子（在GitLab企业版中叫做Git钩子）
> > 4. 执行你请求的动作
> > 5. 处理GitLab的post-receive动作
> > 6. 处理自定义的post-receive动作
> >
> > 当通过http(s)访问GitLab Server时，工作流程取决于你是从Git仓库拉取(pull)代码还是向git仓库推送(push)代码。如果你是从Git仓库拉取(pull)代码，GitLab Rails应用会全权负责处理用户鉴权和执行Git命令的工作；如果你是向Git仓库推送(push)代码，GitLab Rails应用既不会进行用户鉴权也不会执行Git命令，它会把以下工作交由GitLab Shell进行处理：
> >
> > 1. 调用GitLab Rails API 检查权限
> > 2. 执行pre-receive钩子（在GitLab企业版中叫做Git钩子）
> > 3. 执行你请求的动作
> > 4. 处理GitLab的post-receive动作
> > 5. 处理自定义的post-receive动作
> >
> >    > > ​也许你会奇怪在通过http(s)推送(push)代码的情况下，GitLab Rails应用为什么不在GitLab Shell之前进行鉴权。这是因为GitLab Rails应用没有解析`git push`命令的逻辑。好的方法是将这些解析代码放在一个地方，这个地方就是GitLab Shell，这样我们就可以在通过SSH进行访问时重用这段代码。实际上，GitLabShell在执行`git push`命令时根本不会进行权限检查，它是依赖于pre-receive钩子进行权限检查的。而当你执行`git pull`命令时，权限检查是在命令执行之前的。对`git pull`命令的权限检查要简单得多，因为你只需要检查一个用户是否可以访问这个仓库就可以了（不需要检查分支权限）。
> > > >
> > > > 好吧，GitLab Shell这段话都是翻译官网的。链接在这里
> > > > [https://gitlab.com/gitlab-org/gitlab-shell/blob/master/README.md](https://gitlab.com/gitlab-org/gitlab-shell/blob/master/README.md)
> >
> > #### GitLab Workhorse
> >
> > GitLab Workhorse是一个敏捷的反向代理。它会处理一些大的HTTP请求，比如文件上传、文件下载、Git push/pull和Git包下载。其它请求会反向代理到GitLab Rails应用，即反向代理给后端的unicorn。官网对GitLab Workhorse的介绍在这里：[https://gitlab.com/gitlab-org/gitlab-workhorse/](https://gitlab.com/gitlab-org/gitlab-workhorse/)
> >
> > #### GitLab 工作流程：
> >
> > ![](http://oifb0494t.bkt.clouddn.com/16-12-22/80097840-file_1482388715940_15081.png)	

***



#### 我们采用docker镜像安装GitLab：

#### 安装好后会运行以下三个docker 镜像,每个镜像里运行的服务如下图所示：

1. sameersbn/gitlab:8.13.6 
2. sameersbn/postgresql:9.5-3 or sameersbn/mysql 
3. sameersbn/redis:latest

![](http://oifb0494t.bkt.clouddn.com/16-12-22/83354833-file_1482371643853_13ce.png)





### 准备工作：

系统环境：两台阿里云 ECS，操作系统 Ubuntu 14.04.5 LTS (GNU/Linux 3.13.0-86-generic x86_64)

​		注册域名 gitlab.test.acme.cn

​		域名 *.test.acme.cn 的SSL 证书 

​	（如果用自己生成的自签署证书，在后面，用 git 通过https 拉代码时，以及在登录 私有 docker 仓库时，会r报错，所以还是用有效的ssl证书较好） 

#### 如何生成自签署证书，及排错，请见

* [附录](#附录)

* ### 服务器安装

---

### 第一部份：通过 docker 启动 gitlab-ci server 

---

#### 我们采用 docker-compse 启动配置文件 docker-compose.yml,的方式，来运行gitlab-ci server。

##### 1. 安装 docker-compse

> 用root帐号登录进系统,安装docker-compose,建立gitlab目录：

```
默认的，系统已经安装了 docker 
root@node1:~# apt-get update
root@iZbp1cl4i8oy1rng3b9cc7Z:~# docker --version
Docker version 1.12.3, build 47a8b59

root@node1:~# apt-get install linux-image-generic-lts-trusty
root@node1:~# apt-get install python-pip python-dev
root@node1:~# pip install -U docker-compose
root@node1:~# chmod +x /usr/local/bin/docker-compose
root@node1:~# docker-compose -v
docker-compose version 1.9.0, build 2585387
root@node1:~# mkdir /home/gitlab
root@node1:~# cd /home/gitlab
```

##### 2. 生成 docker-compose.yml文件,并运行命令:docker-compose up -d

> ​	gitlab服务运行需要三个部分配合：postgresql、redis数据库、gitlab服务器，这三个服务分别运行在不同的docker里，在下面的docker-compose.yml文件中进行配置。

```
操作步骤如下：

root@node1:/home/gitlab# vi docker-compose.yml
postgresql:
  image: registry.cn-hangzhou.aliyuncs.com/acs-sample/postgresql-sameersbn:9.4-24
  environment:
    - DB_USER=gitlab
    - DB_PASS=password
    - DB_NAME=gitlabhq_production
    - DB_EXTENSION=pg_trgm
  volumes:
    - /srv/docker/gitlab/postgresql:/var/lib/postgresql
gitlab:
  image: registry.cn-hangzhou.aliyuncs.com/acs-sample/gitlab-sameersbn:latest
  links:
    - redis:redisio
    - postgresql:postgresql
  ports:
    - "80:80"
    - "10022:22"
  environment:
    - TZ=Asia/Shanghai
    - SMTP_ENABLED=false
    - SMTP_DOMAIN=www.163.com
    - SMTP_HOST=smtp.163.com
    - SMTP_PORT=587
    - SMTP_USER=bignetshark
    - SMTP_PASS=acme123
    - SMTP_STARTTLS=true
    - SMTP_AUTHENTICATION=login
    - GITLAB_TIMEZONE=Beijing
    - GITLAB_HOST=gitlab.test.acme.cn
    - GITLAB_PORT=80
    - GITLAB_SSH_PORT=22
    - GITLAB_EMAIL=bignetshark@163.com
    - GITLAB_EMAIL_REPLY_TO=bignetshark@163.com
    - GITLAB_BACKUPS=daily
    - GITLAB_BACKUP_TIME=01:00
    - GITLAB_SECRETS_DB_KEY_BASE=long-and-random-alphanumeric-string
  volumes:
    - /srv/docker/gitlab/gitlab:/home/git/data
redis:
  image: registry.cn-hangzhou.aliyuncs.com/acs-sample/redis-sameersbn:latest
  volumes:
    - /srv/docker/gitlab/redis:/var/lib/redis

#将上面文本保存到 docker-compose.yml 中
root@node1:/home/gitlab# ls
docker-compose.yml

#指定-d参数，是指以daemon的方式启动容器
root@node1:/home/gitlab# docker-compose up -d
Pulling redis (registry.cn-hangzhou.aliyuncs.com/acs-sample/redis-sameersbn:latest)...
latest: Pulling from acs-sample/redis-sameersbn
96c6a1f3c3b0: Pull complete
ed40d4bcb313: Pull complete
b171f9dbc13b: Pull complete
.......
Creating gitlab_postgresql_1
Creating gitlab_redis_1
Creating gitlab_gitlab_1

```

#### 这样 gitlab 服务器就成功通过 docker 启动了。

------

> > > ####							注意事项：
> > >
> > > 在下面 gitlab,的环境变量中 邮箱配置 部分，需要根据实际进行调整。

```
SMTP_DOMAIN=www.163.com
    - SMTP_HOST=smtp.163.com
    - SMTP_PORT=587
    - SMTP_USER=bignetshark
    - SMTP_PASS=acme123
    - SMTP_STARTTLS=true
    - SMTP_AUTHENTICATION=login
    - GITLAB_TIMEZONE=Beijing
    - GITLAB_HOST=gitlab.test.acme.cn
    - GITLAB_PORT=80
    - GITLAB_SSH_PORT=22
    - GITLAB_EMAIL=bignetshark@163.com
    - GITLAB_EMAIL_REPLY_TO=bignetshark@163.com
```

> > > 如果配置有误，在提示 修改root密码时 会报这样的错误：

```
 7 errors prohibited this user from being saved:

- Email can't be blank
- Password can't be blank
- Name can't be blank
- Notification email can't be blank
- Notification email is invalid
- Username can contain only letters, digits, '_', '-' and '.'. Cannot start with '-' or end in '.'.
- Username can't be blank
```

***

### 第二部分：Gitlab https 配置

配置SSL 证书的步骤：

1.建立 certs 目录。

2.将生成好的相关域名的（此处是 test.acme.cn) crt 和 key 文件拷贝进去

3.gitlab ssl证书的名称最好设为 gitlab.crt，私钥 gitlab.key. （这样不需要改动配置文件。否则，会导致 https web 服务，启动不起来。

4.修改 key 文件的权限。

```
root@node1:~# mkdir /srv/docker/gitlab/gitlab/certs
root@node1:~# cd /srv/docker/gitlab/gitlab/certs
root@node1:~# chmod 400 gitlab.key
```

然后 修改 docker-compose.yml 文件，增加 GITLAB_HTTPS=true 保存如下：

```
postgresql:
  image: registry.cn-hangzhou.aliyuncs.com/acs-sample/postgresql-sameersbn:9.4-24
  environment:
    - DB_USER=gitlab
    - DB_PASS=password
    - DB_NAME=gitlabhq_production
    - DB_EXTENSION=pg_trgm
  volumes:
    - /srv/docker/gitlab/postgresql:/var/lib/postgresql
gitlab:
  image: registry.cn-hangzhou.aliyuncs.com/acs-sample/gitlab-sameersbn:latest
  links:
    - redis:redisio
    - postgresql:postgresql
  ports:
    - "443:443"
    - "10022:22"
  environment:
    - TZ=Asia/Shanghai
    - SMTP_ENABLED=false
    - SMTP_DOMAIN=www.163.com
    - SMTP_HOST=smtp.163.com
    - SMTP_PORT=587
    - SMTP_USER=bignetshark
    - SMTP_PASS=acme123
    - SMTP_STARTTLS=true
    - SMTP_AUTHENTICATION=login
    - GITLAB_TIMEZONE=Beijing
    - GITLAB_HOST=gitlab.test.acme.cn
    - GITLAB_PORT=443
    - GITLAB_SSH_PORT=22
    - GITLAB_HTTPS=true
    - SSL_SELF_SIGNED=true
    - GITLAB_EMAIL=bignetshark@163.com
    - GITLAB_EMAIL_REPLY_TO=bignetshark@163.com
    - GITLAB_BACKUPS=daily
    - GITLAB_BACKUP_TIME=01:00
    - GITLAB_SECRETS_DB_KEY_BASE=long-and-random-alphanumeric-string
  volumes:
    - /srv/docker/gitlab/gitlab:/home/git/data
redis:
  image: registry.cn-hangzhou.aliyuncs.com/acs-sample/redis-sameersbn:latest
  volumes:
    - /srv/docker/gitlab/redis:/var/lib/redis
```

如果之前 的 gitlab 在运行状态，执行以下命令，将之重启。

```
# 先 down 一下删除原有配置,然后再 up 并以 daemon守护进程的方式运行。
root@node1 :/home/gitlab# docker-compose down
root@node1 :/home/gitlab# docker-compose up -d
Creating gitlab_redis_1
Creating gitlab_postgresql_1
Creating gitlab_gitlab_1
```

也可以执行`docker kill $(docker ps)` ,将所有docker 停止，再`docker-compose up -d` 将服务启动。

这样 https 配置就生效了。



------

### 第三部分：配置 docker registry 2

最好 镜像源地址 改为 国内的。修改方法如下：

```
 修改Docker配置文件/etc/default/docker，在文件最后 加上 DOCKER_OPTS="--registry-mirror=http://aad0405c.m.daocloud.io" 一行。
 操作如下：

root@node1 # vi /etc/default/docker
DOCKER_OPTS="--registry-mirror=http://aad0405c.m.daocloud.io"

root@node1 # service docker restart
做完以上修改，重启docker后，再来 pull 镜像，速度就很快了，例如：
root@node1 # docker pull registry:2
```

#### 实现一个带用户鉴权功能的 Docker Registry HTTPS 配置

> > 第一步：增加 docker registry 用户 foo 及密码 foo123

```
root@node1 # mkdir /srv/docker/gitlab/registry/auth
root@node1 # docker run --entrypoint htpasswd registry:2 -Bbn foo foo123  >> /srv/docker/gitlab/registryauth/htpasswd
```

> > 第二步：启动带鉴权 ssl 功能的Registry，它的证书目录是指定到 gitlab 的 ssl 证书所在目录。

```
root@node1 # docker run -d -p 5000:5000 --restart=always --name registry \
   -v /srv/docker/gitlab/registry/auth:/auth \
   -e "REGISTRY_AUTH=htpasswd" \
   -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
   -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
   -v /srv/docker/gitlab/registry:/var/lib/registry \
   -v /srv/docker/gitlab/gitlab/certs:/certs \
   -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/gitlab.crt \
   -e REGISTRY_HTTP_TLS_KEY=/certs/gitlab.key \
   registry:2
```

------

#### 至此，带用户鉴权功能的 SSL DOCKER REGISTRY 已经启动了。

#### （注意：新增用户后，需要重启Docker Registry ， 用户才能生效。）



#### 测试登录 私有DOCKER 仓库 push docker images ：

```
# 下面将本地ubuntu 镜像 打标签：
root@node2 # docker tag ubuntu gitlab.test.acme.cn:5000/test/ubuntu:latest
# 登录服务器,输入username:foo password:foo123
root@node2 # docker login gitlab.test.acme.cn:5000
Username :
passord :
#现在可以推送镜像了。
root@node2 # docker push gitlab.test.acme.cn:5000/test/ubuntu:latest
#要查看服务器上的镜像，用以下命令：
root@node2 # curl --cacert /etc/docker/certs.d/gitlab.test.acme.cn:5000/gitlab.crt  --basic --user foo:foo123 https://gitlab.test.acme.cn:5000/v2/_catalog

#执行上面命令，就会返回类似如下的镜像列表。

{"repositories":["test/registry","test/ubuntu"]}
```

到此，服务器部分的准备工作完成了。

***



### 第四部分：gitlab 项目代码准备

#### 简单的 Gitlab-CI 项目构建

````
目标：

我们通过在 gitlab 新建一个 nginx 项目，将生成 docker 的 Dockerfile 文件存入其中。

然后新建一个 .gitlab-ci.yml文件 (在文件中写入 nginx docker构建的命令、及docker 仓库登录及推送的命令)，以构建一个 nginx docker 镜像，并将它推送到 docker 仓库中。

最后在.gitlab-ci.yml文件中指定要运行部署脚本 deploy.sh，让另一台服务器，到 docker 仓库中取出这个  nginx docker 镜像，并运行，来完成整个CI过程。
````
* ##### 代码准备工作，把nginx项目的代码从 github 下载下来：

  1. 点击 [ida/nginx](https://gitlab.test.acme.cn/ida/nginx/tree/master) 到 github 页面中。 
  2. 点击“ Download ZIP" 将整个项目文件 nginx-*.zip下载到本地.

  ​

  ***

  ​

* #### gitlab用户注册：

  ```
  流程： 在浏览器中输入 https://gitlab.test.acme.cn	按提示修改管理员 root 的密码，然后再注册新用户。
  我注册了新用户：ytb,密码：acme123
  然后 在浏览器中输入 https://gitlab.test.acme.cn	登录 ytb
  创建新项目：nginx 			
  ```
  ![](http://oifb0494t.bkt.clouddn.com/16-12-20/57749072-file_1482224323317_bf57.png)			

#### 目的：

> > 	在本机建立一个 gitlab-aliyun 的目录，将下载的nginx-master.zip 拷贝到目录下，解压，然后通过      git提交到 gitlab 服务器。
> > 	操作步骤如下：

```
➜  ~ mkdir gitlab-aliyun

➜  ~ cd gitlab-aliyun

➜  gitlab-aliyun cp ~/Desktop/nginx-master.zip ./

➜  gitlab-aliyun ls

nginx-master.zip

➜  gitlab-aliyun unzip nginx-master.zip

Archive:  nginx-master.zip

3b681b96e267f7c3a8c68b3febb04f6b7abb59c3

   creating: nginx-master/

  inflating: nginx-master/Dockerfile

  inflating: nginx-master/LICENSE

  inflating: nginx-master/README.md

  inflating: nginx-master/deploy.sh

➜  gitlab-aliyun ls

nginx-master     nginx-master.zip

➜  gitlab-aliyun rm -rf nginx-master.zip

➜  gitlab-aliyun cd nginx-master

➜  nginx-master ls

Dockerfile LICENSE    README.md  deploy.sh

➜  nginx-master git init

Initialized empty Git repository in /Users/yintb/gitlab-aliyun/nginx-master/.git/

➜  nginx-master git:(master) ✗ git remote add origin https://gitlab.test.acme.cn/ytb/nginx.git

➜  nginx-master git:(master) ✗ git add .

➜  nginx-master git:(master) ✗ git commit -m 'new project'

[master (root-commit) e87e07e] new project

 4 files changed, 90 insertions(+)

 create mode 100644 Dockerfile

 create mode 100644 LICENSE

 create mode 100644 README.md

 create mode 100755 deploy.sh

 ➜  nginx-master git:(master) git push -u origin master

Username for 'https://gitlab.test.acme.cn': ytb

Password for 'https://ytb@gitlab.test.acme.cn':

Counting objects: 6, done.

Delta compression using up to 4 threads.

Compressing objects: 100% (6/6), done.

Writing objects: 100% (6/6), 1.98 KiB | 0 bytes/s, done.

Total 6 (delta 0), reused 0 (delta 0)

To https://gitlab.test.acme.cn/ytb/nginx.git

- [new branch]      master -> master
  Branch master set up to track remote branch master from origin.
```

##### 注意：若使用 git clone,或 git push 等命令时遇到类似如下错误：

```
Permission denied (publickey,password,keyboard-interactive).
fatal: The remote end hung up unexpectedly
```

#####  则需要修改 gitlab 服务器文件 /etc/ssh/sshd_config ，将PasswordAuthentication 项改为 no，然后将服务器 SSHD 服务重启。再到WEB界面，将用户公钥粘到ssh keys下。

```
root@gitlab:/home/gitlab# vi /etc/ssh/sshd_config
PasswordAuthentication no
```

​	![](http://oifb0494t.bkt.clouddn.com/16-12-23/94207545-file_1482479760552_1325.png)



##### 	在gitlab中要配置CI ,必须要在项目的根目录下建立一个   .gitlab-ci.yml 文件，来定义每个步骤，我们下载的文件中已经包含了它，但里面一些参数需要根据自己的情况进行修改：

*   ```

      ➜  nginx git:(master) ✗ vi .gitlab-ci.yml
      before_script:
    - whoami
    - docker info
    variables:
    IMAGE_NAME: "test/nginx"
    build:
    script:
      - docker build -t $IMAGE_NAME .
    push-image-to-registry:
    script:
      - docker tag $IMAGE_NAME gitlab.test.acme.cn:5000/xxx/nginx:latest
      - docker login --username=你自己的docker仓库账号 --password=密码 gitlab.test.acme.cn:5000
      - docker push gitlab.test.acme.cn:5000/xxx/nginx:latest
    deploy_docker:
    script:
      - ./deploy.sh
      
    ```
  ```

  > > 请注意：需要把上面.gitlab-ci.yml 文件中的这部分，替换为自己的相关信息：
  > >
  > > - push-image-to-registry:
  > >     script:
  > >
  > >   - docker tag $IMAGE_NAME gitlab.test.acme.cn:5000/xxx/nginx:latest
  > >
  > >
  > >   - docker login —username=***你自己的docker仓库账号 —password=密码 ***  gitlab.test.acme.cn:5000
  > >     - docker push *** gitlab.test.acme.cn:5000/acme/nginx:latest *** 

 
  ```
​	通过下面命令，把修改提交到 gitlab server.

```
➜  nginx git:(master) ✗ git add .

➜  nginx git:(master) ✗ git commit -m '随便填些内容即可'

➜  nginx git:(master) git push origin master
```



#### 这样，项目的代码部分就准备完了。

***

### 第五部分： gitlab-ci-multi-runner 的安装

***



在GitLab中有个Runners的概念。

 [Gitlab-runner](https://docs.gitlab.com/ce/ci/runners/README.html) 是 `.gitlab-ci.yml` 脚本的运行器，Gitlab-runner是基于Gitlab-CI的API进行构建的相互隔离的机器（或虚拟机）。

Gitlab Runner分为两种，Shared runners和Specific runners。

 Specific runners只能被指定的项目使用，Shared runners则可以运行所有开启 `Allow shared runners` 选项的项目。 

此处，因为只有两台服务器，所以我们把 gitlab-ci-multi-runner 也安装在 gitlab服务器上。另一台作为部署用服务器。

> > 安装 gitlab-ci-multi-runner,运行下面的命令即可（注意，因为网络原因有可能失败，多运行几次即可。）

```
root@node1:~# curl -sSL https://get.docker.com/ | sh && curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-ci-multi-runner/script.deb.sh | sudo bash && sudo apt-get install gitlab-ci-multi-runner && sudo usermod -aG docker gitlab-runner &&  sudo -u gitlab-runner -H docker info
```

然后，在浏览器中打开你的 nginx 项目主页：

![](http://oifb0494t.bkt.clouddn.com/16-12-20/39622342-file_1482224323541_c14c.png)



![](http://oifb0494t.bkt.clouddn.com/16-12-20/30896933-file_1482224323765_83b9.png)	

> 运行 gitlab-ci-multi-runner register ,将上图中的url 和 token 值 填入下面命令中。

```
root@node1:~# gitlab-ci-multi-runner register -n \
--url https://gitlab.test.acme.cn/ci \
--registration-token Yfk_y3mKy3STtBtE3LSg \
--executor shell \
--description "My Runner"


Running in system-mode.

Registering runner... succeeded                     runner=j1q7Lg_f

Runner registered successfully. Feel free to start it, but if it's running already the config should be automatically reloaded!
```

在运行 runner 的服务器 和 要部署的服务器之间，最好配置 ssh 免密码登录（这里是 gitlab-runner 用户，在runner 服务器和 要部署的服务器上都 要有这个用户，并把ruuner 服务器上 gitlab-runner 用户的公钥增加到 部署服务器上 gitlab-runner 用户的 authorized_keys 文件中.

此处是： /home/gitlab-runner/.ssh/authorized_keys  这样会方便部署)。

***

### 第六部分

### 运行CI

上述配置完成后，在你的项目的 runners界面中 会有类似如下图示：

![](http://oifb0494t.bkt.clouddn.com/16-12-22/22793709-file_1482378438847_826e.png)



点击“ pipelines" 就会进行在 .gitlab-ci.yml 文件 中定义的集成步骤：

![](http://oifb0494t.bkt.clouddn.com/16-12-22/96538913-file_1482378510459_f76a.png)

如果一切配置正常，在status 栏，会显示 passed, 若出错，则显示红色的 failed ,点击进入后可查看具体出错的提示。

下图是部署服务器，成功后的显示 ：

![](http://oifb0494t.bkt.clouddn.com/16-12-22/76708414-file_1482378864118_167fc.png)

***



### 							集成了私有docker 仓库的配置文件

##### 下面的 docker-compose.yml 用[sameersbn/docker-gitlab](https://github.com/sameersbn/docker-gitlab/blob/master/docker-compose.yml) 的配置，gitlab:8.13.6 ，其中把 docker 仓库 加入在配置文件中了。

***



```
root@gitlab:/home/gitlab# cat docker-compose.yml
version: '2'

services:
  registry:
    restart: always
    image: registry:2
    ports:
    - "5000:5000"
    environment:
      - REGISTRY_AUTH=htpasswd
      - REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm
      - REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd
      - REGISTRY_HTTP_TLS_CERTIFICATE=/certs/gitlab.crt
      - REGISTRY_HTTP_TLS_KEY=/certs/gitlab.key
    volumes:
      - /srv/docker/gitlab/registry/auth:/auth
      - /srv/docker/gitlab/registry:/var/lib/registry
      - /srv/docker/gitlab/gitlab/certs:/certs

  redis:
    restart: always
    image: sameersbn/redis:latest
    command:
    - --loglevel warning
    volumes:
    - /srv/docker/gitlab/redis:/var/lib/redis:Z

  postgresql:
    restart: always
    image: sameersbn/postgresql:9.5-3
    volumes:
    - /srv/docker/gitlab/postgresql:/var/lib/postgresql:Z
    environment:
    - DB_USER=gitlab
    - DB_PASS=password
    - DB_NAME=gitlabhq_production
    - DB_EXTENSION=pg_trgm

  gitlab:
    restart: always
    image: sameersbn/gitlab:8.13.6
    depends_on:
    - redis
    - postgresql
    ports:
    - "443:443"
    - "10022:22"
    volumes:
    - /srv/docker/gitlab/gitlab:/home/git/data:Z
    environment:
    - DEBUG=false

    - DB_ADAPTER=postgresql
    - DB_HOST=postgresql
    - DB_PORT=5432
    - DB_USER=gitlab
    - DB_PASS=password
    - DB_NAME=gitlabhq_production

    - REDIS_HOST=redis
    - REDIS_PORT=6379

    - TZ=Asia/Shanghai
    - GITLAB_TIMEZONE=Beijing

    - GITLAB_HTTPS=true
    - SSL_SELF_SIGNED=true

    - GITLAB_HOST=gitlab.test.acme.cn
    - GITLAB_PORT=443
    - GITLAB_SSH_PORT=22
    - GITLAB_RELATIVE_URL_ROOT=
    - GITLAB_SECRETS_DB_KEY_BASE=long-and-random-alphanumeric-string
    - GITLAB_SECRETS_SECRET_KEY_BASE=long-and-random-alphanumeric-string
    - GITLAB_SECRETS_OTP_KEY_BASE=long-and-random-alphanumeric-string

    - GITLAB_ROOT_PASSWORD=123456
    - GITLAB_ROOT_EMAIL=bignetshark@163.com

    - GITLAB_NOTIFY_ON_BROKEN_BUILDS=true
    - GITLAB_NOTIFY_PUSHER=false

    - GITLAB_EMAIL=bignetshark@163.com
    - GITLAB_EMAIL_REPLY_TO=bignetshark@163.com
    - GITLAB_INCOMING_EMAIL_ADDRESS=bignetshark@163.com

    - GITLAB_BACKUP_SCHEDULE=daily
    - GITLAB_BACKUP_TIME=01:00

    - SMTP_ENABLED=true
    - SMTP_DOMAIN=www.163.com
    - SMTP_HOST=smtp.163.com
    - SMTP_PORT=587
    - SMTP_USER=bignetshark
    - SMTP_PASS=acme123
    - SMTP_STARTTLS=true
    - SMTP_AUTHENTICATION=login
```

***

# 



#### 附录

#### 生成自签署证书，相关错误及解决方法:

1. 自己配置CA签发SSL 证书的步骤:	

   ```
   mkdir /volume1/docker/gitlab/certs
   cd /volume1/docker/gitlab/certs
   openssl genrsa -out gitlab.key 2048
   openssl req -new -key gitlab.key -out gitlab.csr
   openssl x509 -req -days 3650 -in gitlab.csr -signkey gitlab.key -out gitlab.crt
   openssl dhparam -out dhparam.pem 2048
   chmod 400 gitlab.key
   ```

2. 用自己生成的自签署证书，在客户端用 git 通过https 拉代码时，会报错，`fatal: unable to access 'https://gitlab.test.acme.cn/ytb/txida.git/': SSL certificate problem: Invalid certificate chain` 解决方法：在客户端命令行输入： `git config --global http.sslVerify false`  取消证书验证即可。

   1. **使用自签署证书**，生成 https docker registry, 时用户在 push 时会遇到这样的错误：`x509: certificate signed by unknown authority` , 这是因为自签署的证书是由未知CA签署的，因此验证失败。

       我们需要让docker client安装我们的CA证书：

      ```
      # sudo mkdir -p /etc/docker/certs.d/domain-name.com:5000
      # sudo cp certs/domain-name.crt /etc/docker/certs.d/domain-name.com:5000/ca.crt
      # sudo service docker restart //安装证书后，重启Docker Daemon
      ```

      完成后，再执行Push，就能成功。
