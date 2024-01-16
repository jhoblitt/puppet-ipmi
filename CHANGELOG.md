# Changelog

All notable changes to this project will be documented in this file.
Each new release typically also includes the latest modulesync defaults.
These should not affect the functionality of the module.

## [v5.3.0](https://github.com/jhoblitt/puppet-ipmi/tree/v5.3.0) (2024-01-16)

[Full Changelog](https://github.com/jhoblitt/puppet-ipmi/compare/v5.2.0...v5.3.0)

**Implemented enhancements:**

- ipmi::user: Mask passwords [\#70](https://github.com/jhoblitt/puppet-ipmi/pull/70) ([b4ldr](https://github.com/b4ldr))

## [v5.2.0](https://github.com/jhoblitt/puppet-ipmi/tree/v5.2.0) (2023-10-19)

[Full Changelog](https://github.com/jhoblitt/puppet-ipmi/compare/v5.1.0...v5.2.0)

**Implemented enhancements:**

- allow stdlib 9.x [\#68](https://github.com/jhoblitt/puppet-ipmi/pull/68) ([jhoblitt](https://github.com/jhoblitt))

**Closed issues:**

- stdlib 9.x.x compat [\#63](https://github.com/jhoblitt/puppet-ipmi/issues/63)

## [v5.1.0](https://github.com/jhoblitt/puppet-ipmi/tree/v5.1.0) (2023-06-23)

[Full Changelog](https://github.com/jhoblitt/puppet-ipmi/compare/v5.0.0...v5.1.0)

**Implemented enhancements:**

- add support for puppet8 [\#66](https://github.com/jhoblitt/puppet-ipmi/pull/66) ([jhoblitt](https://github.com/jhoblitt))

## [v5.0.0](https://github.com/jhoblitt/puppet-ipmi/tree/v5.0.0) (2023-03-06)

[Full Changelog](https://github.com/jhoblitt/puppet-ipmi/compare/v4.0.0...v5.0.0)

**Breaking changes:**

- drop puppet6 support \(EOL\) [\#60](https://github.com/jhoblitt/puppet-ipmi/pull/60) ([jhoblitt](https://github.com/jhoblitt))
- drop debian 8 & 9, ubuntu 14.04 & 16.04 support [\#58](https://github.com/jhoblitt/puppet-ipmi/pull/58) ([jhoblitt](https://github.com/jhoblitt))

**Implemented enhancements:**

- Add option to disable users [\#59](https://github.com/jhoblitt/puppet-ipmi/pull/59) ([jcpunk](https://github.com/jcpunk))
- add EL9 support [\#57](https://github.com/jhoblitt/puppet-ipmi/pull/57) ([jhoblitt](https://github.com/jhoblitt))
- add AlmaLinux and Rocky support [\#56](https://github.com/jhoblitt/puppet-ipmi/pull/56) ([jhoblitt](https://github.com/jhoblitt))

## [v4.0.0](https://github.com/jhoblitt/puppet-ipmi/tree/v4.0.0) (2022-09-12)

[Full Changelog](https://github.com/jhoblitt/puppet-ipmi/compare/v3.1.0...v4.0.0)

**Breaking changes:**

- Set the ipmi service to stopped by default if no ipmi devices [\#33](https://github.com/jhoblitt/puppet-ipmi/pull/33) ([jcpunk](https://github.com/jcpunk))

**Closed issues:**

- Missing "openipmi" service on Debian 6, 7, 8 [\#29](https://github.com/jhoblitt/puppet-ipmi/issues/29)

**Merged pull requests:**

- Modulesync 5.3.0 [\#52](https://github.com/jhoblitt/puppet-ipmi/pull/52) ([jhoblitt](https://github.com/jhoblitt))
- Permit password as Sensitive string [\#51](https://github.com/jhoblitt/puppet-ipmi/pull/51) ([jcpunk](https://github.com/jcpunk))
- run all github actions on PRs [\#49](https://github.com/jhoblitt/puppet-ipmi/pull/49) ([jhoblitt](https://github.com/jhoblitt))

## [v3.1.0](https://github.com/jhoblitt/puppet-ipmi/tree/v3.1.0) (2022-04-11)

[Full Changelog](https://github.com/jhoblitt/puppet-ipmi/compare/v3.0.1...v3.1.0)

**Implemented enhancements:**

- Add fact to store information about the BMC [\#48](https://github.com/jhoblitt/puppet-ipmi/pull/48) ([jcpunk](https://github.com/jcpunk))

## [v3.0.1](https://github.com/jhoblitt/puppet-ipmi/tree/v3.0.1) (2022-04-08)

[Full Changelog](https://github.com/jhoblitt/puppet-ipmi/compare/v3.0.0...v3.0.1)

**Closed issues:**

- Dependency cycle [\#34](https://github.com/jhoblitt/puppet-ipmi/issues/34)

**Merged pull requests:**

- update CI badges [\#46](https://github.com/jhoblitt/puppet-ipmi/pull/46) ([jhoblitt](https://github.com/jhoblitt))

## [v3.0.0](https://github.com/jhoblitt/puppet-ipmi/tree/v3.0.0) (2022-04-07)

[Full Changelog](https://github.com/jhoblitt/puppet-ipmi/compare/v2.3.0...v3.0.0)

**Closed issues:**

- Support for Debian 10 [\#42](https://github.com/jhoblitt/puppet-ipmi/issues/42)
- PDK convert + CentOS 8 support? [\#41](https://github.com/jhoblitt/puppet-ipmi/issues/41)
- Issue with Ubuntu [\#27](https://github.com/jhoblitt/puppet-ipmi/issues/27)

**Merged pull requests:**

- 3.0.0 release [\#45](https://github.com/jhoblitt/puppet-ipmi/pull/45) ([jhoblitt](https://github.com/jhoblitt))
- modernize code + plumbing [\#44](https://github.com/jhoblitt/puppet-ipmi/pull/44) ([jhoblitt](https://github.com/jhoblitt))
- Add support for EL8 [\#43](https://github.com/jhoblitt/puppet-ipmi/pull/43) ([neufeind](https://github.com/neufeind))
- update module plumbing [\#40](https://github.com/jhoblitt/puppet-ipmi/pull/40) ([jhoblitt](https://github.com/jhoblitt))
- Bumps stdlib requirements to next major version. [\#39](https://github.com/jhoblitt/puppet-ipmi/pull/39) ([dupgit](https://github.com/dupgit))
- user: Handle more than 19 users correctly [\#37](https://github.com/jhoblitt/puppet-ipmi/pull/37) ([ananace](https://github.com/ananace))
- Update links [\#26](https://github.com/jhoblitt/puppet-ipmi/pull/26) ([petems](https://github.com/petems))

## [v2.3.0](https://github.com/jhoblitt/puppet-ipmi/tree/v2.3.0) (2016-06-30)

[Full Changelog](https://github.com/jhoblitt/puppet-ipmi/compare/v2.2.0...v2.3.0)

**Closed issues:**

- Fact has a few issues [\#24](https://github.com/jhoblitt/puppet-ipmi/issues/24)

**Merged pull requests:**

- Large refactor for IPMI facts: [\#25](https://github.com/jhoblitt/puppet-ipmi/pull/25) ([petems](https://github.com/petems))
- Add Debian based os support [\#23](https://github.com/jhoblitt/puppet-ipmi/pull/23) ([petems](https://github.com/petems))
- Update Readme.md with details on defined resources [\#22](https://github.com/jhoblitt/puppet-ipmi/pull/22) ([ripclawffb](https://github.com/ripclawffb))

## [v2.2.0](https://github.com/jhoblitt/puppet-ipmi/tree/v2.2.0) (2016-06-28)

[Full Changelog](https://github.com/jhoblitt/puppet-ipmi/compare/v2.1.0...v2.2.0)

**Closed issues:**

- error displayed when trying to parse 'which ipmitool' [\#19](https://github.com/jhoblitt/puppet-ipmi/issues/19)
- Enhancement: write BMC config [\#15](https://github.com/jhoblitt/puppet-ipmi/issues/15)

**Merged pull requests:**

- plumbing updates [\#21](https://github.com/jhoblitt/puppet-ipmi/pull/21) ([jhoblitt](https://github.com/jhoblitt))
- added defined resources for network and user configuration [\#20](https://github.com/jhoblitt/puppet-ipmi/pull/20) ([ripclawffb](https://github.com/ripclawffb))
- quote the numbers in the case statement [\#18](https://github.com/jhoblitt/puppet-ipmi/pull/18) ([mmckinst](https://github.com/mmckinst))
- Silence debug output by default [\#17](https://github.com/jhoblitt/puppet-ipmi/pull/17) ([beddari](https://github.com/beddari))

## [v2.1.0](https://github.com/jhoblitt/puppet-ipmi/tree/v2.1.0) (2015-10-14)

[Full Changelog](https://github.com/jhoblitt/puppet-ipmi/compare/v2.0.0...v2.1.0)

**Merged pull requests:**

- IPMI facts \(rebase only, original PR is \#12\) [\#16](https://github.com/jhoblitt/puppet-ipmi/pull/16) ([elisiano](https://github.com/elisiano))

## [v2.0.0](https://github.com/jhoblitt/puppet-ipmi/tree/v2.0.0) (2015-06-06)

[Full Changelog](https://github.com/jhoblitt/puppet-ipmi/compare/v1.2.0...v2.0.0)

**Merged pull requests:**

- Feature/v2.0.0 [\#13](https://github.com/jhoblitt/puppet-ipmi/pull/13) ([jhoblitt](https://github.com/jhoblitt))
- Add support for enabling the IPMI watchdog [\#11](https://github.com/jhoblitt/puppet-ipmi/pull/11) ([bodgit](https://github.com/bodgit))
- Feature/future parser [\#10](https://github.com/jhoblitt/puppet-ipmi/pull/10) ([jhoblitt](https://github.com/jhoblitt))
- consolidate all copyright notices into LICENSE file [\#9](https://github.com/jhoblitt/puppet-ipmi/pull/9) ([jhoblitt](https://github.com/jhoblitt))

## [v1.2.0](https://github.com/jhoblitt/puppet-ipmi/tree/v1.2.0) (2014-09-02)

[Full Changelog](https://github.com/jhoblitt/puppet-ipmi/compare/v1.1.1...v1.2.0)

**Implemented enhancements:**

- Request: Ubuntu Support [\#6](https://github.com/jhoblitt/puppet-ipmi/issues/6)

**Merged pull requests:**

- Feature/v1.2.0 [\#8](https://github.com/jhoblitt/puppet-ipmi/pull/8) ([jhoblitt](https://github.com/jhoblitt))
- Added support for EL7. [\#7](https://github.com/jhoblitt/puppet-ipmi/pull/7) ([razorsedge](https://github.com/razorsedge))

## [v1.1.1](https://github.com/jhoblitt/puppet-ipmi/tree/v1.1.1) (2013-09-21)

[Full Changelog](https://github.com/jhoblitt/puppet-ipmi/compare/v1.1.0...v1.1.1)

**Closed issues:**

- Support for ipmievd. [\#1](https://github.com/jhoblitt/puppet-ipmi/issues/1)

## [v1.1.0](https://github.com/jhoblitt/puppet-ipmi/tree/v1.1.0) (2013-09-14)

[Full Changelog](https://github.com/jhoblitt/puppet-ipmi/compare/v1.0.1...v1.1.0)

**Closed issues:**

- LSB facts are a pain. [\#3](https://github.com/jhoblitt/puppet-ipmi/issues/3)

**Merged pull requests:**

- split ipmi::service class into ipmi::service::{ipmi,ipmievd\) [\#5](https://github.com/jhoblitt/puppet-ipmi/pull/5) ([jhoblitt](https://github.com/jhoblitt))

## [v1.0.1](https://github.com/jhoblitt/puppet-ipmi/tree/v1.0.1) (2013-09-12)

[Full Changelog](https://github.com/jhoblitt/puppet-ipmi/compare/v1.0.0...v1.0.1)

**Merged pull requests:**

- remove usage of $::lsbmajdistrelease fact [\#4](https://github.com/jhoblitt/puppet-ipmi/pull/4) ([jhoblitt](https://github.com/jhoblitt))
- Support for ipmievd. [\#2](https://github.com/jhoblitt/puppet-ipmi/pull/2) ([razorsedge](https://github.com/razorsedge))

## [v1.0.0](https://github.com/jhoblitt/puppet-ipmi/tree/v1.0.0) (2013-08-29)

[Full Changelog](https://github.com/jhoblitt/puppet-ipmi/compare/fd0a99855dae7e5d300b994f018d25be4cb29f67...v1.0.0)



\* *This Changelog was automatically generated by [github_changelog_generator](https://github.com/github-changelog-generator/github-changelog-generator)*
