// vim: sw=2
#![feature(asm)]
#![feature(phase)]
#![feature(macro_rules)]
#![crate_type="staticlib"]
#![no_std]

extern crate core;
extern crate zinc;
#[phase(plugin)] extern crate macro_ioreg;

use core::option::Some;
use zinc::hal::k20::pin;
use zinc::hal::pin::GPIO;
use zinc::hal::cortex_m4::systick;

/// Wait the given number of SysTick ticks
pub fn wait(ticks: u32) {
  let mut n = ticks;
  // Reset the tick flag
  systick::tick();
  loop {
    if systick::tick() {
      watdog_refresh();
      n -= 1;
      if n == 0 {
        break;
      }
    }
  }
}

mod reg {
  use zinc::lib::volatile_cell::VolatileCell;
  use core::ops::Drop;
  use core::option::{Option,Some};

  ioregs!(WDOG = {
    0x0 => reg16 stctrlh
    {
      0 => en,
      4 => allowupdate
    },

    0xc => reg16 refresh {
      0..15 => refresh: wo
      {
        0xa602 => Seq1,
        0xb480 => Seq2,
      },
    },

    0xe => reg16 unlock {
      0..15 => unlock: wo
      {
        0xc520 => Seq1,
        0xd928 => Seq2,
      },
    },

  })

  ioregs!(SIM = {
    0x1030 => reg32 scgc3
    {
      27 => adc1,
      24 => ftm2,
    },

    0x1038 => reg32 scgc5
    {
      13 => porte,
      12 => portd,
      11 => portc,
      10 => portb,
      9 => porta,
      5 => tsi,
      0 => lptimer,
    },

    0x103c => reg32 scgc6
    {
      29 => rtc,
      27 => adc0,
      25 => ftm1,
      24 => ftm0,
      23 => pit,
      22 => pdb,
      21 => usbdcd,
      18 => crc,
      15 => i2s,
      13 => spi1,
      12 => spi0,
      4 => flexcan0,
      1 => dmamux,
      0 => ftfl,
    },
  })

  extern {
    #[link_name="k20_iomem_WDOG"] pub static WDOG: WDOG;
    #[link_name="k20_iomem_SIM"] pub static SIM: SIM;
  }
}

/*
 * TODO: Remove this function once disabling watchdog
 * works
 */
pub fn watdog_refresh() {
  reg::WDOG.refresh.set_refresh(0xa602);
  reg::WDOG.refresh.set_refresh(0xb480);
}


#[no_mangle]
#[no_split_stack]
pub fn main() {
  reg::WDOG.unlock.set_unlock(0xc520);
  reg::WDOG.unlock.set_unlock(0xd928);
  unsafe {
    asm!("nop" :::: "volatile");
    asm!("nop" :::: "volatile");
  }
  reg::WDOG.stctrlh.set_allowupdate(true);
  reg::WDOG.stctrlh.set_en(false);

  zinc::hal::mem_init::init_stack();
  zinc::hal::mem_init::init_data();

  //reg::SIM.scgc5.set_portc(true);

  /*
  reg::SIM.scgc6
    .set_rtc(true)
    .set_ftm0(true)
    .set_ftm1(true)
    .set_adc0(true)
    .set_ftfl(true);
    */

  // Pins for MC HCK (http://www.mchck.org/)
  let led1 = pin::Pin::new(pin::PortC, 5, pin::GPIO, Some(zinc::hal::pin::Out));

  systick::setup(720000, false);
  systick::enable();
  let mut m = 1;
  loop {
    led1.set_high();
    wait(m);
    led1.set_low();
    wait(m);

    m += 1;
  }
}
