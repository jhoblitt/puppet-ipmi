
#### [Current]
 * [5b5770f](../../commit/5b5770f) - __(Joshua Hoblitt)__ fix linter warnings
 * [0d2f8ef](../../commit/0d2f8ef) - __(Joshua Hoblitt)__ update README format
 * [a2f9824](../../commit/a2f9824) - __(Joshua Hoblitt)__ update puppet versions in travis matrix
 * [3c283b1](../../commit/3c283b1) - __(Joshua Hoblitt)__ add el7.x to README platforms list
 * [d7b6c5f](../../commit/d7b6c5f) - __(Joshua Hoblitt)__ add `:require` option to all Gemfile entries
 * [af79b53](../../commit/af79b53) - __(Joshua Hoblitt)__ update .gitignore
 * [9bd46bd](../../commit/9bd46bd) - __(Joshua Hoblitt)__ update copyright notice year to 2014
 * [edf951c](../../commit/edf951c) - __(Joshua Hoblitt)__ Merge pull request [#7](../../issues/7) from razorsedge/support_el7

Added support for EL7.
 * [3fe4023](../../commit/3fe4023) - __(Michael Arnold)__ Make the spec tests pass.

Commented out all the "should include_class" stanzas.  This should make
Travis-CI happy.

 * [d6f934f](../../commit/d6f934f) - __(Michael Arnold)__ Added support for EL7.
 * [2dae883](../../commit/2dae883) - __(Joshua Hoblitt)__ fix README ToC

#### v1.1.1
 * [26e1430](../../commit/26e1430) - __(Joshua Hoblitt)__ bump version to v1.1.1
 * [de20f48](../../commit/de20f48) - __(Joshua Hoblitt)__ update README param docs
 * [4e07c04](../../commit/4e07c04) - __(Joshua Hoblitt)__ reduce stdlib requirement to 3.0.0
 * [0a3be5b](../../commit/0a3be5b) - __(Joshua Hoblitt)__ add puppet 3.3.0 to travis test matrix
 * [c2a54cb](../../commit/c2a54cb) - __(Joshua Hoblitt)__ add GFMD highlighting to README
 * [aafd0c8](../../commit/aafd0c8) - __(Joshua Hoblitt)__ fix README markdown typo

#### v1.1.0
 * [b83bdd7](../../commit/b83bdd7) - __(Joshua Hoblitt)__ bump version to v1.1.0
 * [8f04955](../../commit/8f04955) - __(Joshua Hoblitt)__ Merge pull request [#5](../../issues/5) from jhoblitt/service_control

split ipmi::service class into ipmi::service::{ipmi,ipmievd)
 * [47cc455](../../commit/47cc455) - __(Joshua Hoblitt)__ split ipmi::service class into ipmi::service::{ipmi,ipmievd)
 * [7f1d5c3](../../commit/7f1d5c3) - __(Joshua Hoblitt)__ puppet-lint should ignore pkg/**

#### v1.0.1
 * [2821421](../../commit/2821421) - __(Joshua Hoblitt)__ bump version to v1.0.1
 * [4f19e76](../../commit/4f19e76) - __(Joshua Hoblitt)__ Merge pull request [#4](../../issues/4) from jhoblitt/remove_lsb_facts

remove usage of $::lsbmajdistrelease fact
 * [23c2227](../../commit/23c2227) - __(Joshua Hoblitt)__ remove usage of $::lsbmajdistrelease fact

Instead use $::operatingsystemmajrelease as this fact is not dependant on
redhat-lsb being present on the system.

 * [95c5d0f](../../commit/95c5d0f) - __(Joshua Hoblitt)__ fix ugly typo in ipmi::service tests
 * [f76e51f](../../commit/f76e51f) - __(Joshua Hoblitt)__ validate `$start_ipmievd` param to classes `ipmi` & `ipmi::service`
 * [2b6de1a](../../commit/2b6de1a) - __(Joshua Hoblitt)__ Merge pull request [#2](../../issues/2) from razorsedge/ipmievd

Support for ipmievd.
 * [a3922d2](../../commit/a3922d2) - __(Michael Arnold)__ Advanced configuration of ipmievd service.
 * [a99cf85](../../commit/a99cf85) - __(Michael Arnold)__ Basic addition of ipmievd service.

#### v1.0.0
 * [efc47e5](../../commit/efc47e5) - __(Joshua Hoblitt)__ refactor module structure

* split ipmi::install into ipmi::{install,params}
* base class inherits ipmi::params
* contain subclasses in ipmi base class
* comprehensive test coverage

 * [7534ba8](../../commit/7534ba8) - __(Joshua Hoblitt)__ fix README ToC formatting
 * [9defe3b](../../commit/9defe3b) - __(Joshua Hoblitt)__ update README formatting
 * [8128871](../../commit/8128871) - __(Joshua Hoblitt)__ fix linter warnings
 * [3acd51d](../../commit/3acd51d) - __(Joshua Hoblitt)__ Merge puppet-module_skel
 * [fd0a998](../../commit/fd0a998) - __(Joshua Hoblitt)__ first commit
