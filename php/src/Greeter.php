<?php

declare(strict_types=1);

namespace EasyblobsTest\Hello;

/** A real class the autoloader must find. */
final class Greeter
{
    public static function greet(string $name): string
    {
        return 'hello ' . $name;
    }
}
