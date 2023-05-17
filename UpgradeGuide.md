# Upgrade Guide

Cotes Chung edited this page on Mar 18 · [14 revisions](https://github.com/cotes2020/jekyll-theme-chirpy/wiki/Upgrade-Guide/_history)



The way to update the theme depends on how you use it.

## Upgrade from starter

If you are using the theme gem (there will be `gem "jekyll-theme-chirpy"` in the `Gemfile`), editing the `Gemfile` and update the version number of the theme gem, for example:

```
- gem "jekyll-theme-chirpy", "~> 3.2"
+ gem "jekyll-theme-chirpy", "~> 4.0"
```

And then execute the following command:

```
$ bundle update jekyll-theme-chirpy
```

As the version upgrades, the critical files (for details, see the [startup template](https://github.com/cotes2020/chirpy-starter)) and configuration options will change. We can use the GitHub API to get the file changes in the version upgrade.

The URL format is as follows:

```
https://github.com/cotes2020/chirpy-starter/compare/<older_version>...<newer_version>
```

For instance, to upgrade from `v4.0.0` to `v5.0.0`, visit:
*https://github.com/cotes2020/chirpy-starter/compare/v4.0.0...v5.0.0*

## Upgrade the fork

If you forked from the source project (there will be `gemspec` in the `Gemfile` of your site), then merge the [latest upstream tags](https://github.com/cotes2020/jekyll-theme-chirpy/tags) into your Jekyll site to complete the upgrade. The merge is likely to conflict with your local modifications. Please be patient and careful to resolve these conflicts.

Starting with `v5.6.0`, the JS distribution files have been removed from the repository, so for all future upgrades, you should compile the JS files yourself.

```
npm run build
```

And then make sure to add them to your repository files.

```
git add assets/js/dist -f
```