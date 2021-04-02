# ==================================================
$system_packages = [
'apt-transport-https',
'clang',
'clang-9',
'clang-tools-9',
'clang-10',
'clang-tools-10',
'clang-11',
'clang-tools-11',
'curl',
'debian-archive-keyring',
'debian-keyring',
'emacs',
'gawk',
'git',
'make',
'net-tools',
'wget',
'zstd',
]

package { $system_packages:
  ensure => 'latest'
}

# ==================================================
package { "nginx":
  ensure => absent,
}

# ==================================================
vcsrepo { '/firejail':
  ensure => latest,
  provider => git,
  source => 'https://github.com/netblue30/firejail.git',
  revision => 'LTSbase',
} ->

exec { 'firejail-configure':
  command => '/firejail/configure',
  cwd => '/firejail',
  subscribe => Vcsrepo['/firejail'],
  refreshonly => true,
} ->

exec { 'firejail-make':
  command => '/usr/bin/make install-strip',
  cwd => '/firejail',
  subscribe => Vcsrepo['/firejail'],
  refreshonly => true,
}

# ==================================================

exec { "setup-openresty-1":
  command => '/usr/bin/wget -O - https://openresty.org/package/pubkey.gpg | /usr/bin/apt-key add -',
  unless => '/usr/bin/ls /etc/apt/sources.list.d/openresty.list',
} ->

exec { "setup-openresty-2":
  command => '/usr/bin/echo "deb http://openresty.org/package/ubuntu focal main" | /usr/bin/tee /etc/apt/sources.list.d/openresty.list',
  unless => '/usr/bin/ls /etc/apt/sources.list.d/openresty.list',
} ->

exec { "setup-openresty-3":
  command => '/usr/bin/apt-get update'
} ->

package { 'openresty':
  ensure => 'latest',
} ->

package { "lua5.1":
  ensure => latest,
} ->

file_line { env-2:
  ensure => present,
  path => "/etc/environment",
  line => "discovery_url=https://auth.mozilla.auth0.com/.well-known/openid-configuration"
} ->

file_line { env-3:
  ensure => present,
  path => "/etc/environment",
  line => "backend=http://localhost:10240"
} ->

file_line { env-4:
  ensure => present,
  path => "/etc/environment",
  line => "httpsredir=no"
} ->

file { '/etc/nginx/nginx.conf':
  ensure => file,
  source => 'https://github.com/mozilla-iam/mozilla.oidc.accessproxy/raw/master/etc/nginx.conf',
  notify  => Service['openresty']
} ->

file { '/etc/nginx/conf.d/nginx_lua.conf':
  ensure => file,
  source => 'https://github.com/mozilla-iam/mozilla.oidc.accessproxy/raw/master/etc/conf.d/nginx_lua.conf',
  notify  => Service['openresty']
} ->

file_line { 'resolver-replace':
    path      => '/etc/nginx/conf.d/nginx_lua.conf',
    replace => true,
    line       => "resolver 8.8.8.8 8.8.4.4;",
    match  => "resolver 127.0.0.11; # Docker networking's DNS"
} ->

file { '/etc/nginx/conf.d/openidc_layer.lua':
  ensure => file,
  source => 'https://github.com/mozilla-iam/mozilla.oidc.accessproxy/raw/master/etc/conf.d/openidc_layer.lua',
  notify  => Service['openresty']
} ->

file { '/etc/nginx/conf.d/proxy_auth_bypass.conf':
  ensure => file,
  source => 'https://github.com/mozilla-iam/mozilla.oidc.accessproxy/raw/master/etc/conf.d/proxy_auth_bypass.conf',
  notify  => Service['openresty']
} ->

file { '/etc/nginx/conf.d/server.conf':
  ensure => file,
  source => 'https://github.com/mozilla-iam/mozilla.oidc.accessproxy/raw/master/etc/conf.d/server.conf',
  notify  => Service['openresty']
} ->

file { '/etc/nginx/conf.d/server.lua':
  ensure => file,
  source => 'https://github.com/mozilla-iam/mozilla.oidc.accessproxy/raw/master/etc/conf.d/server.lua',
  notify  => Service['openresty']
} ->

file_line { 'server-replace':
    path      => '/etc/nginx/conf.d/server.lua',
    replace => true,
    line       => "app_name = 'compiler-explorer'",
    match  => "app_name = 'proxied_app'"
} ->

service { 'openresty':
  ensure => running
}


# ==================================================

exec { 'download-clang':
  command => '/usr/bin/wget -q https://firefox-ci-tc.services.mozilla.com/api/index/v1/task/gecko.cache.level-1.toolchains.v3.linux64-clang-11.latest/artifacts/public/build/clang.tar.zst',
  cwd => '/',
  unless => '/usr/bin/ls /mozilla-clang-11'
} ->

exec { 'unzip-clang':
  command => '/usr/bin/unzstd clang.tar.zst',
  cwd => '/',
  unless => '/usr/bin/ls /mozilla-clang-11',
} ->

exec { 'untar-clang':
  command => '/usr/bin/tar xf clang.tar',
  cwd => '/',
  unless => '/usr/bin/ls /mozilla-clang-11',
} ->

exec { 'move-clang':
  command => '/usr/bin/mv clang mozilla-clang-11',
  cwd => '/',
  unless => '/usr/bin/ls /mozilla-clang-11',
}

# ==================================================
exec { 'setup-node':
  command => '/usr/bin/curl -sL https://deb.nodesource.com/setup_12.x | /usr/bin/bash -',
  unless => '/usr/bin/ls /etc/apt/sources.list.d/nodesource.list',
} ->

package { 'nodejs':
  ensure => 'latest',
} ->

vcsrepo { '/ce':
  ensure => latest,
  provider => git,
  source => 'https://github.com/compiler-explorer/compiler-explorer.git',
  revision => '3c2aa307e1a2dbda3c6eb4ac6052a6a6689e6bd6',
} ->

file { '/ce/etc/config/execution.local.properties':
  ensure => file,
  source => 'https://raw.githubusercontent.com/mozilla-services/civet-docker/main/execution.mozilla.properties'
} ->

file { '/ce/etc/config/c++.local.properties':
  ensure => file,
  source => 'https://raw.githubusercontent.com/mozilla-services/civet-docker/main/c%2B%2B.mozilla.properties'
} ->

file { '/ce/views/resources/site-logo.svg':
  ensure => file,
  source => 'https://raw.githubusercontent.com/mozilla-services/civet-docker/main/ce-mozilla.svg'
} ->

file { '/etc/systemd/system/ce.service':
  ensure => file,
  source => 'https://raw.githubusercontent.com/mozilla-services/civet-docker/main/ce.service'
} ->

service { 'ce':
  ensure => running,
  require => [ Exec['move-clang'], Exec['firejail-make'], Service['openresty']]
}

# ==================================================

vcsrepo { '/civet-docker':
  ensure => latest,
  provider => git,
  source => 'https://github.com/mozilla-services/civet-docker.git',
  revision => 'puppet',
} ->

cron { 'puppet-apply':
  ensure => present,
  command => '/usr/bin/puppet apply /civet-docker/ce.pp',
  user => 'root',
  minute => ['0', '5']
}