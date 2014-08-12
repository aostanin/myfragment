#! /usr/bin/env python3

import argparse
import os
import sys
import time

import numpy
import pyqrcode
from PySide import QtCore, QtGui

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('-i', '--image', nargs=5, required=True, help='Input image (5 total)')
    parser.add_argument('-u', '--url', required=False, help='URL for the QR code')

    return parser.parse_args()


def create_qr_code(url):
    qrcode = pyqrcode.create(url)
    w = len(qrcode.code[0])
    h = len(qrcode.code)
    image_data = numpy.ones((w, h, 4), numpy.uint8, 'C')

    for j, row in enumerate(qrcode.code):
        for i, item in enumerate(row):
            if item == 0:
                image_data[j, i] = (255, 255, 255, 255)
            else:
                image_data[j, i] = (0, 0, 0, 255)

    return QtGui.QImage(image_data, w, h, QtGui.QImage.Format_ARGB32)


def print_card(images, card_size=(148, 100)):
    app = QtGui.QApplication(sys.argv)

    printer = QtGui.QPrinter()

    #printer.setCopyCount(2)
    printer.setOrientation(QtGui.QPrinter.Landscape)
    printer.setFullPage(True)
    printer.setPaperSize(QtCore.QSize(card_size[0], card_size[1]), QtGui.QPrinter.Millimeter)

    fn = os.path.dirname(__file__) + '/print_' + time.strftime('%Y%m%d%H%M%S') + '.pdf'
    printer.setOutputFileName(fn)

    painter = QtGui.QPainter()
    painter.begin(printer)

    page_rect = printer.pageRect()
    image_rect = QtCore.QRect(0, 0, page_rect.width() / 3, page_rect.height() / 2)

    rects = []

    images.append(QtGui.QImage(os.path.dirname(__file__) + '/logo.png'))

    for image in images:
        scaled_image = image.scaled(image_rect.size(), QtCore.Qt.KeepAspectRatio)
        adjusted_rect = QtCore.QRect(image_rect)
        adjusted_rect.setSize(scaled_image.size())
        if image_rect.top() >= image_rect.height():
            dy = 0
        else:
            dy = image_rect.height() - scaled_image.height()
        adjusted_rect.translate((image_rect.width() - scaled_image.width()) / 2, dy)
        painter.drawImage(adjusted_rect, image)
        rects.append(adjusted_rect)

        image_rect.translate(image_rect.width(), 0)
        if image_rect.right() > page_rect.width():
            image_rect.moveTop(image_rect.height())
            image_rect.moveLeft(0)

    subtitleFont = QtGui.QFont()
    subtitleFont.setFamily('Helvetica Neue')
    subtitleFont.setPixelSize(8)
    subtitleFont.setWeight(QtGui.QFont.Normal)

    painter.setFont(subtitleFont)

    dateRect = rects[3]
    dateRect.moveLeft(dateRect.left() + 2)
    dateRect.moveTop(dateRect.bottom() + 2)
    dateRect.setHeight(10)

    painter.drawText(dateRect, time.strftime('%Y/%m/%d'))

    urlRect = rects[4]
    urlRect.moveLeft(urlRect.left() + 2)
    urlRect.moveTop(urlRect.bottom() + 2)
    urlRect.setHeight(10)

    painter.drawText(urlRect, 'kaigoto.com')

    painter.end()

    #os.system('lpr -#2 -o landscape -o page-left=0 -o page-right=0 -o page-top=0 -o page-bottom=0 -o media=Custom.100x148mm -P Brother_HL_2270DW_series ' + fn)


if __name__ == '__main__':
    args = parse_args()

    #qrcode = create_qr_code(args.url)

    images = [QtGui.QImage(fn) for fn in args.image]
    if not all(not image.isNull() for image in images):
        raise Exception('Failed to load one or more images')

    print_card(images)
