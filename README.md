# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version
* System dependencies
* Configuration
* Database creation
* Database initialization
* How to run the test suite
* Services (job queues, cache servers, search engines, etc.)
* Deployment instructions
* ...

# run

1. crontab: 
    - `whenever -i` for crontab updating
    - `whenever -w` for crontab execute.
    - `crontab -l` for scheduled job listing.
2. `redis-server` for start redis server.
3. `bundle exec sidekiq` for start sidekiq server.
4. `sudo service cron start` make sure crontab is running.

> or set to start when computer starts: `sudo visudo`  
> and add line: `%sudo ALL=NOPASSWD: /usr/sbin/service cron start`  
> press Ctrl+o then Ctrl+x to save and exit.

5. set windows task scheduler to start a task when computer starts
  - program: `C:\Windows\System32\wsl.exe`
  - argument `sudo /usr/sbin/service cron start`

# current env

### System

64-bit installations of Windows10 professional ver 2004 with OS 19041.985
and wsl Ubuntu 20.04.2 LTS

### Ruby on Rails

Using rbenv for ruby 3.0.1 and Rails 6.1.4 installation

### Git

Git-2.32.0.2-64-bit
SourceTreeSetup-3.4.5

### pg under windows
postgresql-10.17-2-windows-x64

notice that postgresql system was installed with the same location as my OS system(SSD) but data was set to another hareware(HDD) with different Disk name.
