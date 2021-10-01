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
=======
# moneyonrails

develop env setup is basically the same as this article
https://gorails.com/setup/windows/10

using 64-bit installations of Windows10 professional ver 2004 with OS 19041.985
`enable Microsoft-Windows-Subsystem-Linux`
`enable VirtualMachinePlatform`
and install Ubuntu 20.04.2 LTS from microsoft store

then
Using rbenv for ruby 3.0.1 and Rails 6.1.4 installation

and some else was from installer like 
Git-2.32.0.2-64-bit.exe/SourceTreeSetup-3.4.5.exe/postgresql-10.17-2-windows-x64.exe

and the system now (maybe there's some COPIED command that resulted to version upgrade while debugging.)
psql (13.3 (Ubuntu 13.3-1.pgdg20.04+1), server 12.7 (Ubuntu 12.7-0ubuntu0.20.04.1)) 

notice that postgresql system was installed with the same location as my OS system(SSD) but data was set to another hareware(HDD) with different Disk name.

to run on localhost with https://
`rails s -b 'ssl://localhost:3000?key=./localhost.key&cert=./localhost.crt'`

issues:
1. ubuntu user name is some thing like this NAME_REGEX="^[a-z][-a-z0-9_]*$" and things like RAILS(uppercase) is not allowed
2. i chose C rather than [Default locale] on postgresql installation. like the step 7. in this article
https://blog.csdn.net/u012325865/article/details/81951916
3. to use postgresql, make sure your username setting like premission / cluster setting, 
make sure your postgresql is running before trying to connect from rails. 
like the step 1.6 in this article (my host name is localhost and the article is localhost_presql)
https://blog.csdn.net/hadues/article/details/103757594
4. To connect postgresql with localhost, try to new a user from pgAdmin 4 rather than from ubuntu command line, 
not sure what's wrong with my setup but i found those users created from command line are somehow not sync or show in pgAdmin.
5. if username permission things bother you a lot, try to ALTER ROLE as superuser or simply use username: postgres password: postgres.
6. the fisrst time i do rails new myapp and some Operation not permitted failed occurrd, the solution can be things like this 
`sudo umount /mnt/c sudo mount -t drvfs C: /mnt/c -o metadata`
and make sure to delete files from incomplete rails new command first
https://devblogs.microsoft.com/commandline/chmod-chown-wsl-improvements/
https://www.ruby-forum.com/t/i-am-trying-to-install-ruby-on-rails-on-windows-10-but-need-help/253284
7. My rails app can't connect to my postgres server as first before i add "host: localhost" in database.yml
8. for fatal:LF would be replaced by CRLF issue, i force my files to windows(CRLF) by sublime text 
{ "default_line_ending": "windows" } since i'm using windows.
`git config --global core.safecrlf true`
`git config --global core.autocrlf true`