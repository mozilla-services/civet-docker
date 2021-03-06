# ==================================================
$system_packages = [
'apt-transport-https',
'bison',
'cgroup-tools',
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
'flex',
'gawk',
'git',
'jq',
'libnl-3-dev',
'libnl-route-3-dev',
'make',
'mercurial',
'net-tools',
'pkg-config',
'protobuf-compiler',
'wget',
'zstd',
]

package { $system_packages:
  ensure => 'latest'
} ->

exec { 'rustup-1':
  command => '/usr/bin/snap install rustup --classic',
} ->

exec { 'rustup-2':
  command => '/snap/bin/rustup toolchain install stable',
}

# ==================================================
package { "nginx":
  ensure => absent,
}

# ==================================================
vcsrepo { '/nsjail':
  ensure => present,
  provider => git,
  source => 'https://github.com/google/nsjail.git',
  revision => '3.0',
} ->

exec { 'nsjail-make':
  command => '/usr/bin/make',
  cwd => '/nsjail',
  environment => [ 'CC=clang', 'CXX=clang++', 'CXXFLAGS="-I/usr/include/libnl3"', 'LDFLAGS="-L/usr/lib/x86_64-linux-gnu/ -lnl-3 -lnl-route-3"']
} ->

exec { 'cgroup-create':
  command => '/usr/bin/cgcreate -a ubuntu:ubuntu -g memory,pids,cpu,net_cls:ce-compile'
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

package { 'openresty-opm':
  ensure => 'latest',
} ->

exec { "setup-openresty-4":
  command => '/usr/bin/opm install zmartzone/lua-resty-openidc=1.6.1',
  environment => [ 'HOME=/root' ],
  unless => '/usr/bin/opm list | /usr/bin/grep lua-resty-openidc'
} ->

package { "lua5.1":
  ensure => latest,
} ->

file { '/etc/systemd/system/openresty.service.d/':
  ensure => 'directory',
} ->

file { '/etc/systemd/system/openresty.service.d/override.conf':
  ensure => file,
  source => '/civet-docker/override.conf'
} ->

exec { 'setup-env-secret-1':
  command => '/usr/bin/echo \'Environment="client_id=\'$(/usr/bin/curl "https://secretmanager.googleapis.com/v1/projects/moz-dev-fx-tritter-compilerexp/secrets/compiler-explorer-client-id/versions/latest:access" \
    --request "GET" \
    --header "authorization: Bearer `/snap/bin/gcloud auth print-access-token`" \
    --header "content-type: application/json" \
    --header "x-goog-user-project: moz-dev-fx-tritter-compilerexp" \
    | /usr/bin/jq -r ".payload.data" | /usr/bin/base64 --decode)\'"\' >> /etc/systemd/system/openresty.service.d/override.conf',
  unless => '/usr/bin/grep client_id=S /etc/systemd/system/openresty.service.d/override.conf',
} ->

exec { 'setup-env-secret-2':
  command => '/usr/bin/echo \'Environment="client_secret=\'$(/usr/bin/curl "https://secretmanager.googleapis.com/v1/projects/moz-dev-fx-tritter-compilerexp/secrets/compiler-explorer-client-secret/versions/latest:access" \
    --request "GET" \
    --header "authorization: Bearer `/snap/bin/gcloud auth print-access-token`" \
    --header "content-type: application/json" \
    --header "x-goog-user-project: moz-dev-fx-tritter-compilerexp" \
    | /usr/bin/jq -r ".payload.data" | /usr/bin/base64 --decode)\'"\' >> /etc/systemd/system/openresty.service.d/override.conf',
  unless => '/usr/bin/grep client_secret=K /etc/systemd/system/openresty.service.d/override.conf',
} ~>

exec { 'setup-env-secret-3':
  command => '/usr/bin/systemctl daemon-reload',
} ->

file { '/etc/openresty/conf.d/':
  ensure => 'directory',
} ->

file { '/etc/openresty/nginx.conf':
  ensure => file,
  source => 'https://raw.githubusercontent.com/mozilla-iam/mozilla.oidc.accessproxy/76c7ef9b40a2f983b902977bafebc9e688e1ab61/etc/nginx.conf',
  replace => true,
  notify  => Service['openresty']
} ->

file { '/etc/openresty/conf.d/nginx_lua.conf':
  ensure => file,
  source => 'https://raw.githubusercontent.com/mozilla-iam/mozilla.oidc.accessproxy/76c7ef9b40a2f983b902977bafebc9e688e1ab61/etc/conf.d/nginx_lua.conf',
  replace => false,
  notify  => Service['openresty']
} ->

file_line { 'resolver-replace':
    path      => '/etc/openresty/conf.d/nginx_lua.conf',
    replace => true,
    line       => "resolver 8.8.8.8 8.8.4.4;",
    match  => "resolver 127.0.0.11; # Docker networking's DNS"
} ->

file_line { 'ca-replace':
    path      => '/etc/openresty/conf.d/nginx_lua.conf',
    replace => true,
    line       => 'lua_ssl_trusted_certificate "/etc/ssl/certs/ca-certificates.crt";',
    match  => 'lua_ssl_trusted_certificate "/etc/ssl/certs/ca-bundle.crt";'
} ->

file { '/etc/openresty/conf.d/openidc_layer.lua':
  ensure => file,
  source => 'https://raw.githubusercontent.com/mozilla-iam/mozilla.oidc.accessproxy/76c7ef9b40a2f983b902977bafebc9e688e1ab61/etc/conf.d/openidc_layer.lua',
  replace => false,
  notify  => Service['openresty']
} ->

file { '/etc/openresty/conf.d/proxy_auth_bypass.conf':
  ensure => file,
  source => 'https://raw.githubusercontent.com/mozilla-iam/mozilla.oidc.accessproxy/76c7ef9b40a2f983b902977bafebc9e688e1ab61/etc/conf.d/proxy_auth_bypass.conf',
  replace => false,
  notify  => Service['openresty']
} ->

file { '/etc/openresty/conf.d/server.conf':
  ensure => file,
  source => '/civet-docker/server.conf',
  notify  => Service['openresty']
} ->

file { '/etc/openresty/conf.d/server.lua':
  ensure => file,
  source => 'https://raw.githubusercontent.com/mozilla-iam/mozilla.oidc.accessproxy/76c7ef9b40a2f983b902977bafebc9e688e1ab61/etc/conf.d/server.lua',
  replace => false,
  notify  => Service['openresty']
} ->

file_line { 'server-replace':
    path      => '/etc/openresty/conf.d/server.lua',
    replace => true,
    line       => "app_name = 'compiler-explorer'",
    match  => "app_name = 'proxied_app'"
} ->

service { 'openresty':
  ensure => running
}


# ==================================================

exec { 'download-clang':
  command => '/usr/bin/wget -q https://firefox-ci-tc.services.mozilla.com/api/index/v1/task/gecko.cache.level-1.toolchains.v3.linux64-clang-12.latest/artifacts/public/build/clang.tar.zst',
  cwd => '/',
  unless => '/usr/bin/ls /mozilla-clang-12'
} ->

exec { 'unzip-clang':
  command => '/usr/bin/unzstd clang.tar.zst',
  cwd => '/',
  unless => '/usr/bin/ls /mozilla-clang-12',
} ->

exec { 'untar-clang':
  command => '/usr/bin/tar xf clang.tar',
  cwd => '/',
  unless => '/usr/bin/ls /mozilla-clang-12',
} ->

exec { 'move-clang':
  command => '/usr/bin/mv clang mozilla-clang-12',
  cwd => '/',
  unless => '/usr/bin/ls /mozilla-clang-12',
} ->

exec { 'cleanup-clang':
  command => '/usr/bin/rm -f clang.* public*',
  cwd => '/',
}

# ==================================================
exec { 'setup-node':
  command => '/usr/bin/curl -sL https://deb.nodesource.com/setup_12.x | /usr/bin/bash -',
  unless => '/usr/bin/ls /etc/apt/sources.list.d/nodesource.list',
} ->

package { 'nodejs':
  ensure => 'latest',
} ->

file { '/opt/':
  ensure => 'directory',
} ->

vcsrepo { '/opt/compiler-explorer':
  ensure => present,
  provider => git,
  source => 'https://github.com/tomrittervg/compiler-explorer.git',
  revision => 'mozilla-main',
  notify  => Service['ce']
} ->

file { '/opt/compiler-explorer/etc/config/execution.local.properties':
  ensure => file,
  source => '/civet-docker/execution.mozilla.properties',
  notify  => Service['ce']
} ->

file { '/opt/compiler-explorer/etc/config/c++.local.properties':
  ensure => file,
  source => '/civet-docker/c++.mozilla.properties',
  notify  => Service['ce']
} ->

file { '/opt/compiler-explorer/etc/nsjail/execute.cfg':
  ensure => file,
  source => '/civet-docker/execute.cfg',
  notify  => Service['ce']
}

file { '/opt/compiler-explorer/views/resources/site-logo.svg':
  ensure => file,
  source => '/civet-docker/ce-mozilla.svg',
  notify  => Service['ce']
} ->

file { '/etc/systemd/system/ce.service':
  ensure => file,
  source => '/civet-docker/ce.service',
  notify  => Service['ce']
} ->

service { 'ce':
  ensure => running,
  require => [ Exec['move-clang'], Exec['cgroup-create'], Service['openresty']]
}

# ==================================================

vcsrepo { '/mozilla-central':
  ensure => latest,
  provider => hg,
  source => 'https://hg.mozilla.org/mozilla-central/',
} ->

file { '/mozilla-central/.mozconfig':
  content => "mk_add_options AUTOCLOBBER=1\nmk_add_options MOZ_OBJDIR=objdir\nac_add_options --enable-bootstrap\n",
} ->

exec { 'build-export-2':
  command => '/mozilla-central/mach create-mach-environment',
  cwd => '/mozilla-central',
  environment => [ 'HOME=/root' ]
} ->

exec { 'build-export-3':
  command => '/mozilla-central/mach build export',
  cwd => '/mozilla-central',
  environment => [ 'HOME=/root' ],
  returns => 1
} ->

# We do it with a -tmp directory we replace in case the headers

file { '/mozilla-libs/':
  ensure => 'directory',
} ->

file { '/mozilla-libs-tmp/':
  ensure => 'directory',
} ->

exec { 'headers-1':
  command => '/civet-docker/get_mozbuild_exports.py -i /mozilla-central/ -o /mozilla-libs-tmp/',
} ->

exec { 'headers-2':
  command => '/usr/bin/rm -r /mozilla-libs/ && mv /mozilla-libs-tmp/ /mozilla-libs/'
}


# ==================================================

vcsrepo { '/civet-docker':
  ensure => latest,
  provider => git,
  source => 'https://github.com/mozilla-services/civet-docker.git',
  revision => 'main'
} ->

cron { 'puppet-apply':
  ensure => present,
  command => '/usr/bin/puppet apply /civet-docker/ce.pp',
  user => 'root',
  minute => ['0', '5']
}