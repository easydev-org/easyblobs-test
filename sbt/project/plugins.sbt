resolvers += Resolver.url(
  "easyblobs-ivy",
  url(sys.env.getOrElse("EASYBLOBS_BASE", "http://127.0.0.1:8080/artifacts/ivy") + "/")
)(Resolver.ivyStylePatterns)
