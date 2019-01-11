using TimeZones: Class, Transition

@testset "Class" begin
    @testset "construct" begin
        @test Class.NONE == Class(0x00)
        @test Class.FIXED == Class(0x01)
        @test Class.VARIABLE == Class(0x02)
        @test Class.STANDARD == Class(0x04)
        @test Class.LEGACY == Class(0x08)

        @test Class.DEFAULT == Class(0x01 | 0x04)
        @test Class.ALL == Class(0x0f)
    end

    @testset "getproperty field fallback" begin
        @test Class isa DataType
        @test sprint(show, Class) == "Class"
    end

    @testset "classify" begin
        fixed_tz = FixedTimeZone("UTC")
        variable_tz = VariableTimeZone(
            "Variable",
            [Transition(DateTime(1900), FixedTimeZone("VST", 0, 0))],
        )

        @test TimeZones.classify(fixed_tz) == Class.FIXED
        @test TimeZones.classify(variable_tz) == Class.VARIABLE

        @test TimeZones.classify(fixed_tz, "northamerica") == Class.FIXED | Class.STANDARD
        @test TimeZones.classify(fixed_tz, "etcetera") == Class.FIXED | Class.LEGACY
        @test TimeZones.classify(fixed_tz, "backward") == Class.FIXED | Class.LEGACY

        @test TimeZones.classify(fixed_tz, ["europe", "backward"]) == Class.FIXED | Class.STANDARD | Class.LEGACY
    end

    @testset "bitwise-or" begin
        @test Class(0x00) | Class(0x00) == Class(0x00)
        @test Class(0x00) | Class(0x01) == Class(0x01)
        @test Class(0x01) | Class(0x00) == Class(0x01)
        @test Class(0x01) | Class(0x01) == Class(0x01)
    end

    @testset "bitwise-and" begin
        @test Class(0x00) & Class(0x00) == Class(0x00)
        @test Class(0x00) & Class(0x01) == Class(0x00)
        @test Class(0x01) & Class(0x00) == Class(0x00)
        @test Class(0x01) & Class(0x01) == Class(0x01)
    end

    @testset "labels" begin
        @test TimeZones.labels(Class.NONE) == ["NONE"]
        @test TimeZones.labels(Class.FIXED) == ["FIXED"]
        @test TimeZones.labels(Class.VARIABLE) == ["VARIABLE"]
        @test TimeZones.labels(Class.STANDARD) == ["STANDARD"]
        @test TimeZones.labels(Class.LEGACY) == ["LEGACY"]

        @test TimeZones.labels(Class.DEFAULT) == ["FIXED", "STANDARD"]
        @test TimeZones.labels(Class.ALL) == ["FIXED", "STANDARD", "LEGACY"]

        @test TimeZones.labels(Class(0x10)) == String[]
    end

    @testset "string" begin
        @test string(Class.DEFAULT) == "FIXED | STANDARD"
    end

    @testset "repr" begin
        @test repr(Class.DEFAULT) == "Class.FIXED | Class.STANDARD"
    end
end
