window.BENCHMARK_DATA = {
  "lastUpdate": 1790342099560,
  "repoUrl": "https://github.com/NexusDynamic/liblsl.dart",
  "entries": {
    "liblsl.dart benchmarks": [
      {
        "commit": {
          "author": {
            "email": "zeyus@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "committer": {
            "email": "zeyus@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "distinct": true,
          "id": "14256750c4a3085a91626b16afc1def031112f66",
          "message": "Stop tracking benchmark output",
          "timestamp": "2026-09-25T15:01:45+02:00",
          "tree_id": "d22a5f3c33378583dea923f99367e70d247fcae6",
          "url": "https://github.com/NexusDynamic/liblsl.dart/commit/14256750c4a3085a91626b16afc1def031112f66"
        },
        "date": 1790341528449,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p50",
            "value": 110.13003124560328,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p95",
            "value": 128.57224609774676,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p99",
            "value": 212.4135078247491,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10238.05419532664,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19485.620726555906,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20249.096273431634,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p50",
            "value": 72.19854688855776,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p95",
            "value": 87.67574999524186,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p99",
            "value": 100.13160937205612,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 9863.093539053125,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19099.26363282466,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 19945.474749988534,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p50",
            "value": 179.6468437476051,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p95",
            "value": 241.80452342648096,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p99",
            "value": 272.82704687081605,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10387.621710947315,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19759.624062487546,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20498.23555469743,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "zeyus@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "committer": {
            "email": "zeyus@zeyus.com",
            "name": "zeyus",
            "username": "zeyus"
          },
          "distinct": true,
          "id": "765af1307e03f8e63d6a449d6c4a2d55d5e39c32",
          "message": "fix android build",
          "timestamp": "2026-09-25T15:11:18+02:00",
          "tree_id": "ce72743e526dd790799c05f38400bad3ae8b1196",
          "url": "https://github.com/NexusDynamic/liblsl.dart/commit/765af1307e03f8e63d6a449d6c4a2d55d5e39c32"
        },
        "date": 1790342098141,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p50",
            "value": 106.66281249882559,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p95",
            "value": 132.90339063587453,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz latency_p99",
            "value": 222.76759375472466,
            "unit": "us"
          },
          {
            "name": "directSync/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10170.284046864708,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19168.798453137017,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20115.974929694858,
            "unit": "us"
          },
          {
            "name": "directSync/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p50",
            "value": 70.3798281165291,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p95",
            "value": 85.74410938422261,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz latency_p99",
            "value": 99.48071874532616,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10277.502781264047,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19276.831843740183,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20145.951296882457,
            "unit": "us"
          },
          {
            "name": "directSyncBlocking/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p50",
            "value": 179.667281258844,
            "unit": "us",
            "extra": "n=4497"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p95",
            "value": 250.07852343605919,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz latency_p99",
            "value": 293.5150468772463,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushSample/8ch@500Hz time_per_sample",
            "value": 2001.33422281521,
            "unit": "us/sample",
            "extra": "500 samples/s, loss 0.0%"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p50",
            "value": 10218.877757807832,
            "unit": "us",
            "extra": "n=8928"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p95",
            "value": 19367.898812504336,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz latency_p99",
            "value": 20338.291296866373,
            "unit": "us"
          },
          {
            "name": "isolateAsync/pushChunkTyped32/64ch@1000Hz time_per_sample",
            "value": 1008.0645161290323,
            "unit": "us/sample",
            "extra": "992 samples/s, loss 0.0%"
          }
        ]
      }
    ]
  }
}