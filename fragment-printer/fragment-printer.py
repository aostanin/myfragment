#! /usr/bin/env python3

import argparse
import os
import sys

import numpy
import pyqrcode
from PySide import QtCore, QtGui

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('-i', '--image', nargs=5, required=True, help='Input image (5 total)')
    parser.add_argument('-u', '--url', required=True, help='URL for the QR code')

    return parser.parse_args()


def create_qr_code(url):
    qrcode = pyqrcode.create(url)
    w = len(qrcode.code[0])
    h = len(qrcode.code)
    image_data = numpy.ones((w, h, 4), numpy.uint8, 'C')

    for j, row in enumerate(qrcode.code):
        for i, item in enumerate(row):
            if item == 0:
                image_data[i, j] = (0, 0, 0, 255)
            else:
                image_data[i, j] = (255, 255, 255, 255)

    return QtGui.QImage(image_data, w, h, QtGui.QImage.Format_ARGB32)


def print_card(images, qrcode, url, card_size=(148, 100)):
    app = QtGui.QApplication(sys.argv)

    printer = QtGui.QPrinter()

    printer.setOrientation(QtGui.QPrinter.Landscape)
    printer.setColorMode(QtGui.QPrinter.GrayScale)
    printer.setPageMargins(0, 0, 0, 0, QtGui.QPrinter.Millimeter)
    printer.setPaperSize(QtCore.QSize(card_size[1], card_size[0]), QtGui.QPrinter.Millimeter)

    printer.setOutputFileName(os.path.dirname(__file__) + '/print.pdf')

    painter = QtGui.QPainter()
    painter.begin(printer)

    page_rect = printer.pageRect()
    image_rect = QtCore.QRect(0, 0, page_rect.width() / 3, page_rect.height() / 2)

    for image in images:
        image = image.scaled(image_rect.size(), QtCore.Qt.KeepAspectRatio)
        adjusted_rect = QtCore.QRect(image_rect)
        adjusted_rect.setSize(image.size())
        adjusted_rect.translate((image_rect.width() - image.width()) / 2, (image_rect.height() - image.height()) / 2)
        painter.drawImage(adjusted_rect, image)

        image_rect.translate(image_rect.width(), 0)
        if image_rect.right() > page_rect.width():
            image_rect.moveTop(image_rect.height())
            image_rect.moveLeft(0)

    qr_side_margin = image_rect.width() * 0.25
    qr_top_margin = image_rect.height() * 0.1
    qr_size = min(image_rect.width(), image_rect.height()) - 2 * qr_side_margin
    qr_rect = QtCore.QRect(image_rect.x() + qr_side_margin, image_rect.y() + qr_top_margin, qr_size, qr_size)
    qrcode = qrcode.scaled(qr_rect.size(), QtCore.Qt.KeepAspectRatio)
    painter.drawImage(qr_rect, qrcode)

    painter.end()


if __name__ == '__main__':
    args = parse_args()

    qrcode = create_qr_code(args.url)

    images = [QtGui.QImage(fn) for fn in args.image]
    if not all(not image.isNull() for image in images):
        raise Exception('Failed to load one or more images')

    print_card(images, qrcode, args.url)
