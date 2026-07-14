# Changelog

## [1.1.0](https://github.com/MTomBosch/cicd-workflows/compare/daily/v1.0.0...daily/v1.1.0) (2026-07-14)


### Features

* add cache debugging to docs workflow ([#90](https://github.com/MTomBosch/cicd-workflows/issues/90)) ([829b3e1](https://github.com/MTomBosch/cicd-workflows/commit/829b3e11ccbf924a5782f7bfed647cb1619fdf78))
* add support for Bazel test targets in QNX build workflow ([#92](https://github.com/MTomBosch/cicd-workflows/issues/92)) ([d4c32d1](https://github.com/MTomBosch/cicd-workflows/commit/d4c32d1da017cb74c1e966072a611266ce9ae312))
* **bzlmod-lock-check:** split into two jobs, add lockfile check, guard against pull_request_target ([#122](https://github.com/MTomBosch/cicd-workflows/issues/122)) ([93aac16](https://github.com/MTomBosch/cicd-workflows/commit/93aac16ada7d247bbb6ae926509ddea74cf5213a))
* daily updates of score modules ([#104](https://github.com/MTomBosch/cicd-workflows/issues/104)) ([cc74a4e](https://github.com/MTomBosch/cicd-workflows/commit/cc74a4e8e355e9ab49d29ae1fcd76912198a8252))
* docs support for private repos ([#99](https://github.com/MTomBosch/cicd-workflows/issues/99)) ([f4c434f](https://github.com/MTomBosch/cicd-workflows/commit/f4c434fa877c0f1ee98425fc3d3ccb0b24e5c77f))
* Enable linux-sandbox in QNX workflow ([#116](https://github.com/MTomBosch/cicd-workflows/issues/116)) ([dfc6ffa](https://github.com/MTomBosch/cicd-workflows/commit/dfc6ffae7b8db630dbf49865314df6c46802d385))
* fail QNX build on empty score-qnx-license secret ([#57](https://github.com/MTomBosch/cicd-workflows/issues/57)) ([f47fb06](https://github.com/MTomBosch/cicd-workflows/commit/f47fb066e83e3875f7cec0f08d0a44c38696391d))
* **formatter:** update default bazel target to include error output for formatting check ([#128](https://github.com/MTomBosch/cicd-workflows/issues/128)) ([f57b605](https://github.com/MTomBosch/cicd-workflows/commit/f57b605a284ca117bcfd9f83ea427096faaac7d1))
* provide on-pr workflow for all the basics checks that we need ([#89](https://github.com/MTomBosch/cicd-workflows/issues/89)) ([61f0b21](https://github.com/MTomBosch/cicd-workflows/commit/61f0b21c81481ddfb556ca379b0e840aca32a72b))
* **qnx-build:** update QNX SDP setup action version ([#112](https://github.com/MTomBosch/cicd-workflows/issues/112)) ([39939c9](https://github.com/MTomBosch/cicd-workflows/commit/39939c97ac17f9e262860cf325bdd52d4a2d21a5))
* **renovate:** run on more repos ([#130](https://github.com/MTomBosch/cicd-workflows/issues/130)) ([55ba887](https://github.com/MTomBosch/cicd-workflows/commit/55ba8872c8a529eb5ab6c4adb0d4b48baf2d2b7a))
* **shared:** add more-disk-space action to several workflows ([#114](https://github.com/MTomBosch/cicd-workflows/issues/114)) ([af34772](https://github.com/MTomBosch/cicd-workflows/commit/af347722c7ae3ed85518895c11268d96ac728f62))
* skip QNX workflow approval for same repo pull requests ([#93](https://github.com/MTomBosch/cicd-workflows/issues/93)) ([97ae51f](https://github.com/MTomBosch/cicd-workflows/commit/97ae51fa5f00e9a5d6ad05d3a542f339f627aacb))
* use setup-qnx-sdp composite action in qnx-build workflow ([#107](https://github.com/MTomBosch/cicd-workflows/issues/107)) ([87fc8be](https://github.com/MTomBosch/cicd-workflows/commit/87fc8bea8901821e3c44f1a9a91b3d2ee066a8f2))


### Bug Fixes

* add missing version.txt for release-please simple strategy ([c647f40](https://github.com/MTomBosch/cicd-workflows/commit/c647f40fc234ee70a8bee271cb7436e0c1f2782c))
* add version.txt for release-please simple strategy ([137b11b](https://github.com/MTomBosch/cicd-workflows/commit/137b11be23a8cc6a1e234f34075ae8d22da4d7f1))
* add workflows:write permission and remove version.txt ([ff7c5a5](https://github.com/MTomBosch/cicd-workflows/commit/ff7c5a561b10ea7375a0d8b7f60ff4a62f92614a))
* align cpp cov runner to rust cov ([#127](https://github.com/MTomBosch/cicd-workflows/issues/127)) ([ea19fca](https://github.com/MTomBosch/cicd-workflows/commit/ea19fcae9aeeb4ac678b750c6c197eaf75414f39))
* avoid gh-pages worktree conflict by isolating cleanup in subdirectory ([#27](https://github.com/MTomBosch/cicd-workflows/issues/27)) ([f363679](https://github.com/MTomBosch/cicd-workflows/commit/f36367925625066eacd86f9f5d6a741305ecd552))
* daily workflow ([#88](https://github.com/MTomBosch/cicd-workflows/issues/88)) ([714336d](https://github.com/MTomBosch/cicd-workflows/commit/714336dfaf196983ef637a7e072512129ade63f9))
* disable graphviz cache ([#32](https://github.com/MTomBosch/cicd-workflows/issues/32)) ([fae1f09](https://github.com/MTomBosch/cicd-workflows/commit/fae1f094d9db2581e48969c9ac754aecbf9d5e1a))
* Do not remove Android SDK from Github runner in QNX workflow ([#129](https://github.com/MTomBosch/cicd-workflows/issues/129)) ([0d27a2f](https://github.com/MTomBosch/cicd-workflows/commit/0d27a2f54f06fd701f4597895aa08d0138f8ebf9))
* **docs:** prevent concurrent Pages deployments from conflicting ([#131](https://github.com/MTomBosch/cicd-workflows/issues/131)) ([1de063a](https://github.com/MTomBosch/cicd-workflows/commit/1de063a34046aa2b09e390fb4059105f2fb2ac6a))
* **docs:** queue pending Pages deployments instead of dropping them ([#132](https://github.com/MTomBosch/cicd-workflows/issues/132)) ([17318d2](https://github.com/MTomBosch/cicd-workflows/commit/17318d27366522721504b60040590dc822264a38))
* on-pr workflow for PRs from forks ([#91](https://github.com/MTomBosch/cicd-workflows/issues/91)) ([ba56c36](https://github.com/MTomBosch/cicd-workflows/commit/ba56c361771cc01e8ec1c7542cf6eaa9c6cf6fdc))
* only save docs cache on push to main ([#103](https://github.com/MTomBosch/cicd-workflows/issues/103)) ([186ace7](https://github.com/MTomBosch/cicd-workflows/commit/186ace77e09aa61bda581e5130aca70b7ec3ed06))
* release docs cleanup ([#69](https://github.com/MTomBosch/cicd-workflows/issues/69)) ([bd16fcc](https://github.com/MTomBosch/cicd-workflows/commit/bd16fcc59f5a7d99ed6ed31b87c5a7db9e43cbf9))
* Update bazel cache on "merge_group" event ([#97](https://github.com/MTomBosch/cicd-workflows/issues/97)) ([ac25d66](https://github.com/MTomBosch/cicd-workflows/commit/ac25d669e392955be86ac87cc7ce3a56e2a6b838)), closes [#95](https://github.com/MTomBosch/cicd-workflows/issues/95)
* update deployment actions to use GitHub's native concurrency key ([#78](https://github.com/MTomBosch/cicd-workflows/issues/78)) ([00a811b](https://github.com/MTomBosch/cicd-workflows/commit/00a811b6bb943663fd9c1bfa06b7aedbcf6bd807))


### Reverts

* "fix: Update bazel cache on "merge_group" event ([#97](https://github.com/MTomBosch/cicd-workflows/issues/97))" ([#98](https://github.com/MTomBosch/cicd-workflows/issues/98)) ([34e9902](https://github.com/MTomBosch/cicd-workflows/commit/34e9902ba18dc1331044e283288577957b40a81c))
