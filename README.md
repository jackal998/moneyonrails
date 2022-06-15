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

=======
# run
1. check gem whenever working run `whenever -i` for crontab updating, then `whenever -w` for crontab execute.
use `crontab -l` for scheduled job listing and config ruby file is ./config/schedule.rb, log file is ./log/cron.log
2. start redis server `redis-server`
3. start sidekiq server `bundle exec sidekiq`
4. make sure crontab is running `sudo service cron start`, or set to start when computer starts:
  `sudo visudo` and add line: `%sudo ALL=NOPASSWD: /usr/sbin/service cron start`
  press Ctrl+o then Ctrl+x to save and exit.

  set windows task scheduler to start a task when computer starts => program:
  `C:\Windows\System32\wsl.exe` and argument `sudo /usr/sbin/service cron start`
=======
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
