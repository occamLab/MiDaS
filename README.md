# Real-time object detection using LiDAR and image-based depth prediction

## Overview

This repository contains an iPhone app that can be used for obstacle detection while navigating. The app currently works with LiDAR phones, and we are in the process of integrating the MiDaS neural network as another way to detect objects. MiDaS depth prediction is based on images captured by the camera instead of LiDAR. To see more of our work on MiDaS depth prediction and object detection, see the [DepthBenchmarking repo](https://github.com/occamLab/DepthBenchmarking). The app detects objects in the camera view and gives auditory feedback about the distance the closest object is from the camera. Currently, the user can toggle between feet and meters.

## Usage

To use the app, clone the repository and follow the steps in the README in the `ios` folder to install all of the necessary packages. The app currently only works on iPhones equipped with LiDAR.

## Acknowledgements

The base of our app was adopted from the [original MiDaS repo](https://github.com/isl-org/midas) and the work of [this paper](https://arxiv.org/abs/1907.01341v3).

>Towards Robust Monocular Depth Estimation: Mixing Datasets for Zero-shot Cross-dataset Transfer  
René Ranftl, Katrin Lasinger, David Hafner, Konrad Schindler, Vladlen Koltun

