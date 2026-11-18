/*
 * This file is part of the µOS++ project (https://micro-os-plus.github.io/).
 * Copyright (c) 2026 Liviu Ionescu. All rights reserved.
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose is hereby granted, under the terms of the MIT license.
 *
 * If a copy of the license was not distributed with this file, it can be
 * obtained from https://opensource.org/licenses/mit.
 */

// ----------------------------------------------------------------------------
//
// The board's LED, for the portable tests (tests/sources/): upstream's
// blink_led (its blinky, tests/platforms/<P>/include/blink-led.h), with the
// same power_up () / blink () / power_down (), plus turn_on () / turn_off ()
// for the tests that show an on/off edge.
//
// One copy for the boards of this workspace, whose board code all has the
// same led.hpp (led::init (), on (), off ()): the Luckfox Lyra's GPIO1_A0, the
// Raspberry Pis' ACT or user LED, the native board's printed edges. A platform
// whose LED is different puts its own blink-led.h in its include/, which is
// searched first.

#ifndef UOS_TESTS_BLINK_LED_H_
#define UOS_TESTS_BLINK_LED_H_

#include <led.hpp>

class blink_led
{
public:
  blink_led ()
  {
    // No hardware changes on constructors.
  }

  void
  power_up ()
  {
    led::init ();
    on_ = false;
  }

  void
  turn_on ()
  {
    led::on ();
    on_ = true;
  }

  void
  turn_off ()
  {
    led::off ();
    on_ = false;
  }

  void
  blink ()
  {
    if (on_)
      {
        turn_off ();
      }
    else
      {
        turn_on ();
      }
  }

  void
  power_down ()
  {
    turn_off ();
  }

private:
  bool on_ = false;
};

#endif // UOS_TESTS_BLINK_LED_H_
