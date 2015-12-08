# ping_of_shame
Reports when our dev Canvas apps are accidentally left running

## Requires the heroku-cli-buildpack
https://github.com/heroku/heroku-buildpack-ruby
```
heroku buildpacks:set heroku/ruby
heroku buildpacks:add --index 1 https://github.com/GoBoundless/heroku-cli-buildpack.git
```
