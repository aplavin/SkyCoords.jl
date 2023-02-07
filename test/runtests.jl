using AstroAngles
using ConstructionBase: setproperties
using DelimitedFiles
using LinearAlgebra: normalize
using SkyCoords
using SkyCoords: project, origin
using StableRNGs
using Statistics
using Test

import SkyCoords: lat, lon

const rng = StableRNG(2000)
rad2arcsec(r) = 3600 * rad2deg(r)

# tests against astropy.coordinates
include("astropy.jl")

@testset "projected coords" begin
    c0 = ICRSCoords(0.1, -0.2)
    c1 = ICRSCoords(0.1 + 1e-5, -0.2 + 3e-5)
    cp = project(c0, c1)::ProjectedCoords
    @test origin(cp) == c0
    @test cp.offset[1] ≈ 0.98 * 1e-5  rtol=1e-4
    @test cp.offset[2] ≈ 3e-5
    @test convert(ICRSCoords, cp) ≈ c1
    @test convert(GalCoords, cp) ≈ convert(GalCoords, c1)
    @test cp == cp
    @test cp ≈ cp
end

# Test separation between coordinates and conversion with mixed floating types.
@testset "Separation" begin
    c1 = ICRSCoords(ℯ, pi / 2)
    c5 = ICRSCoords(ℯ, 1 + pi / 2)
    @test separation(c1, c5) ≈ separation(c5, c1) ≈ separation(c1, convert(GalCoords, c5)) ≈
          separation(convert(FK5Coords{1980}, c5), c1) ≈ 1
    for T in (GalCoords, FK5Coords{2000})
        c2 = convert(T{Float32}, c1)
        c3 = convert(T{Float64}, c1)
        c4 = convert(T{BigFloat}, c1)
        @test typeof(c2) === T{Float32}
        @test typeof(c3) === T{Float64}
        @test typeof(c4) === T{BigFloat}
        @test isapprox(c2, c3, rtol = sqrt(eps(Float32)))
        @test isapprox(c3, c4, rtol = sqrt(eps(Float64)))
        c6 = convert(T, c5)
        @test separation(c3, c6) ≈ separation(c6, c3) ≈ 1
    end
end

@testset "string construction" for C in [
    ICRSCoords,
    GalCoords,
    FK5Coords{2000},
    FK5Coords{1970},
]
    @test C(hms"0h0m0", dms"0d0m0") == C(0.0, 0.0)
    @test C(hms"12h0.0m0.0s", dms"90:0:0") == C(π, π / 2)
    @test C(hms"18h0:0", dms"90:0:0") == C(3π / 2, π / 2)
    @test C(hms"12:0:0", dms"90:0:0") == C(π, π / 2)
end

# Test separation between coordinates and conversion with mixed floating types.
@testset "Position Angles" begin
    c1 = ICRSCoords(0, 0)
    c2 = ICRSCoords(deg2rad(1), 0)

    # interface
    @test @inferred position_angle(c1, c2) ≈ @inferred position_angle(c1, c2 |> GalCoords)
    @test position_angle(c1, c2) ≈ position_angle(c1, c2 |> GalCoords)
    
    # accuracy
    @test position_angle(c1, c2) ≈ π / 2

    c3 = ICRSCoords(deg2rad(1), deg2rad(0.1))
    @test position_angle(c1, c3) < π / 2

    c4 = ICRSCoords(0, deg2rad(1))
    @test position_angle(c1, c4) ≈ 0

    # types
    for T in [ICRSCoords, GalCoords, FK5Coords{2000}]
        c1 = T(0, 0)
        c2 = T(deg2rad(1), 0)
        @test position_angle(c1, c2) ≈ π / 2
    end
end



@testset "Offset ($T1, $T2)" for T1 in [ICRSCoords, GalCoords, FK5Coords{2000}], T2 in [ICRSCoords, GalCoords, FK5Coords{2000}]
    # simple integration tests, depend that separation and position_angle are accurate
    c1s = [
        T1(0, -π/2), # south pole
        T1(0, π/2), # north pole
        T1(deg2rad(1), deg2rad(2))
    ]
    c2 = T2(deg2rad(5), deg2rad(10))

    for c1 in c1s
        sep, pa = @inferred offset(c1, c2)
        test_c2 = @inferred offset(c1, sep, pa)
        @test test_c2 isa T1
        test_c2 = T2(test_c2) 
        @test test_c2 ≈ c2
    end

    # specific cases to cover special cases.
    c1 = T1(0, deg2rad(89))
    for (pa, sep) in [(0, 2), (180, 358)]
        sep = deg2rad(sep)
        pa = deg2rad(pa)
        c2 = offset(c1, sep, pa)
        @test lon(c2) |> rad2deg ≈ 180
        @test lat(c2) |> rad2deg ≈ 89

        c2 = offset(c1, 2sep, pa)
        @test lon(c2) |> rad2deg ≈ 180
        @test lat(c2) |> rad2deg ≈ 87
    end

    # verify antipode
    c1 = T1(deg2rad(10), deg2rad(47))
    for pa in range(0, stop=377, length=10)
        c2 = offset(c1, deg2rad(180), deg2rad(pa))
        @test lon(c2) |> rad2deg ≈ 190
        @test lat(c2) |> rad2deg ≈ -47

        c2 = offset(c1, deg2rad(360), deg2rad(pa))
        @test lon(c2) |> rad2deg ≈ 10
        @test lat(c2) |> rad2deg ≈ 47
    end

    c1 = T1(deg2rad(10), deg2rad(60))
    c2 = offset(c1, deg2rad(1), deg2rad(90))
    @test 11.9 < lon(c2) |> rad2deg < 12.0
    @test 59.9 < lat(c2) |> rad2deg < 60.0
end

@testset "cartesian" begin
    for CT in [ICRSCoords, FK5Coords{2000}, FK5Coords{1975}, GalCoords]
        @test cartesian(CT(0, 0)) |> vec ≈ [1, 0, 0]
        @test cartesian(CT(0, π/2)) |> vec ≈ [0, 0, 1]
        @test cartesian(CT(π/2, 0)) |> vec ≈ [0, 1, 0]
        @test spherical(CartesianCoords{CT}(1, 0, 0)) ≈ CT(0, 0)
        @test spherical(CartesianCoords{CT}(normalize([1, 2, 3]))) ≈ CT(atan(2, 1), atan(3, sqrt(5)))

        c = CT(2, 1)
        c3 = cartesian(c)
        @test c === spherical(c)
        @test c3 === cartesian(c3)
        c_conv = convert(ICRSCoords, c)
        c3_conv = convert(CartesianCoords{ICRSCoords}, c3)
        @test c3_conv == CartesianCoords{ICRSCoords}(c3)
        @test cartesian(c_conv) ≈ c3_conv
        @test c_conv ≈ spherical(c3_conv)

        c_conv3 = convert(CartesianCoords{GalCoords}, c_conv)
        c3_conv = convert(CartesianCoords{GalCoords}, c3_conv)
        @test c_conv3 == CartesianCoords{GalCoords}(c_conv)
        @test c3_conv == CartesianCoords{GalCoords}(c3_conv)
        @test c_conv3 ≈ c3_conv
    end

    a = ICRSCoords(1, 2)
    b = GalCoords(1, 2)
    a3 = cartesian(a)
    b3 = cartesian(b)
    @test separation(a, b) ≈ separation(a3, b3) ≈ separation(a, b3) ≈ separation(a3, b)
end

@testset "constructionbase" begin
    @test setproperties(ICRSCoords(1, 2), ra=3) == ICRSCoords(3, 2)
    @test setproperties(GalCoords(1, 2), l=3) == GalCoords(3, 2)
    @test setproperties(FK5Coords{2000}(1, 2), ra=3) == FK5Coords{2000}(3, 2)
    @test setproperties(cartesian(ICRSCoords(1, 2)), vec=[1., 0, 0]) == cartesian(ICRSCoords(0, 0))
end

@testset "equality" begin
    @testset for T in [ICRSCoords, GalCoords, FK5Coords{2000}]
        c1 = T(1., 2.)
        c2 = T(1., 2.001)
        c3 = T{Float32}(1., 2.)
        c4 = T{Float32}(1., 2.001)
        @test c1 == c1
        @test_broken c1 == c3
        @test c1 ≈ c1
        @test c1 ≈ c3
        @test !(c1 ≈ c2)
        @test !(c1 ≈ c4)
        @test c1 ≈ c2  rtol=1e-3
        @test c1 ≈ c4  rtol=1e-3

        @test ICRSCoords(eps(), 1) ≈ ICRSCoords(0, 1)
        @test ICRSCoords(eps(), 1) ≈ ICRSCoords(-eps(), 1)
    end
 
    @test_broken (!(ICRSCoords(1, 2) ≈ FK5Coords{2000}(1, 2)); true)
    @test_broken (!(FK5Coords{2000}(1, 2) ≈ FK5Coords{1950}(1, 2)); true)
end

@testset "conversion" begin
    systems = (ICRSCoords, FK5Coords{2000}, FK5Coords{1975}, GalCoords)
    for IN_SYS in systems, OUT_SYS in systems
        coord_in = IN_SYS(rand(rng), rand(rng))
        coord_out = convert(OUT_SYS, coord_in)
        # Test pipe and constructor conversion
        @test coord_out == OUT_SYS(coord_in)
        @test coord_out == coord_in |> OUT_SYS
    end
end
