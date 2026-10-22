using Test
using EasyblobsTestHello

@testset "greet" begin
    @test EasyblobsTestHello.greet("easyblobs") == "hello easyblobs"
end
