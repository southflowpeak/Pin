/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {}

/** Preferences accessible in all the extension's commands */
declare type Preferences = ExtensionPreferences

declare namespace Preferences {
  /** Preferences accessible in the `pin-active-window` command */
  export type PinActiveWindow = ExtensionPreferences & {}
  /** Preferences accessible in the `unpin` command */
  export type Unpin = ExtensionPreferences & {}
  /** Preferences accessible in the `status` command */
  export type Status = ExtensionPreferences & {}
  /** Preferences accessible in the `launch-agent` command */
  export type LaunchAgent = ExtensionPreferences & {}
  /** Preferences accessible in the `select-window` command */
  export type SelectWindow = ExtensionPreferences & {}
}

declare namespace Arguments {
  /** Arguments passed to the `pin-active-window` command */
  export type PinActiveWindow = {}
  /** Arguments passed to the `unpin` command */
  export type Unpin = {}
  /** Arguments passed to the `status` command */
  export type Status = {}
  /** Arguments passed to the `launch-agent` command */
  export type LaunchAgent = {}
  /** Arguments passed to the `select-window` command */
  export type SelectWindow = {}
}

