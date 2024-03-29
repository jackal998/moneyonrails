## 從全新的Win10到成功運作的伺服器

## 概述

自從win10有原生子系統功能之後，開發環境就不再限於MacOS，或linux
本篇目的為如何使用 WSL / WSL2 的方式在windows的系統底下用Ubuntu進行開發。

### WSL2

截至2022年，windows有提供兩個版本的wsl，此篇為WSL version 2的部屬方式。
本篇參考(Install Ruby On Rails on Windows 10)[https://gorails.com/setup/windows/10]

#### 開啟子系統功能

以系統管理員身分(Sudo)開啟`Windows PowerShell`

```
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
```
或是
```
enable Microsoft-Windows-Subsystem-Linux
enable VirtualMachinePlatform
```

#### 從 WSL 1 升級至 WSL 2 的版本

可以參考(安裝 WSL)[https://docs.microsoft.com/zh-tw/windows/wsl/install]
以及(舊版 WSL 的手動安裝步驟)[https://docs.microsoft.com/zh-tw/windows/wsl/install-manual#step-3---enable-virtual-machine-feature]

```
wsl --install
wsl --set-default-version 2
```

或是將已經安裝好的wsl升版`wsl --set-version <distro name> 2`

```
wsl --set-version Ubuntu-20.04 2
```
*可能需要下載最新套件(步驟 4 - 下載 Linux 核心更新套件)[https://docs.microsoft.com/zh-tw/windows/wsl/install-manual#step-4---download-the-linux-kernel-update-package]

確定wsl版本
```
wsl -l -v
```

ps 也可以直接用wsl下載Ubuntu

#### 下載/安裝Ubuntu

開啟`Microsoft Store`或是直接下載(20.04 LTS)[https://www.microsoft.com/store/productId/9MTTCL66CPXJ]。

版本看自己需求

#### 安裝Ruby

開啟Ubuntu

```
sudo apt-get update
sudo apt-get install git-core curl zlib1g-dev build-essential libssl-dev libreadline-dev libyaml-dev libsqlite3-dev sqlite3 libxml2-dev libxslt1-dev libcurl4-openssl-dev software-properties-common libffi-dev
```

安裝`rbenv`

```
cd
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init -)"' >> ~/.bashrc
exec $SHELL

git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
echo 'export PATH="$HOME/.rbenv/plugins/ruby-build/bin:$PATH"' >> ~/.bashrc
exec $SHELL
```

安裝Ruby 3.0.1

```
rbenv install 3.0.1
rbenv global 3.0.1
ruby -v
```

安裝bundler

```
gem install bundler
rbenv rehash
```

#### 安裝Rails + Nodejs


Nodejs

```
curl -sL https://deb.nodesource.com/setup_12.x | sudo -E bash -
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list

sudo apt update
sudo apt-get install -y nodejs yarn

npm install
```

Rails

```
gem install rails -v 6.1.4
rbenv rehash
rails -v
```

#### 安裝postgresql

```
sudo apt update
sudo apt install postgresql postgresql-contrib
sudo service postgresql start
```

進入psql

```
sudo -i -u postgres
psql
```

建立使用者

```
postgres=# CREATE USER rails with password 'moneyonrails';
```

建立db

```
CREATE database moneyonrails;
```

#### 安裝webpacker

```
cd <moneyonrails root>
bundle install
bin/rails webpacker:install
```

compile

```
rake webpacker:compile
```

#### 安裝Redis

```
sudo apt install redis-server
```
```
sudo vi /etc/security/limits.conf
```

加入這一行
`* hard nofile 10032`

然後設定root密碼

```
sudo passwd root
```

```
su root
echo never > /sys/kernel/mm/transparent_hugepage/enabled
su <your name>
ulimit -n 10032
```

重新開啟ubuntu

*開新的terminal (PowerShell)
```
wsl --shutdown
```

重新打開Ubuntu

```
sysctl vm.overcommit_memory=1
redis-server
```

#### start server

```
rails s -b 'ssl://localhost:3000?key=./localhost.key&cert=./localhost.crt'
```
Or
```
rails s -b 'ssl://0.0.0.0:3000?key=./localhost.key&cert=./localhost.crt'
```


bundle exec sidekiq