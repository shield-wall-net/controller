from flask import Flask, request, redirect, Response, jsonify
from waitress import serve

from ..config import API_PORT
from boxes import get_box

app = Flask('ShieldWall API')
BAD_BOX_UUID = jsonify({'error': 'Invalid box'})
MISSING_PARAM = jsonify({'error': 'Missing parameter'})


@app.route('/<path:path>')
def catch_all(path):
    del path
    return jsonify({'error': 'Invalid route'}), 400


@app.route('/box/config/available', methods=['GET'])
def box_config_available():
    if 'uuid' not in request:
        return BAD_BOX_UUID, 400

    box = get_box(request['uuid'])
    if box is None:
        return BAD_BOX_UUID, 404

    return jsonify({'available': not box.config_up_to_date()})


@app.route('/box/pkg/available', methods=['GET'])
def box_config_available():
    if 'uuid' not in request:
        return BAD_BOX_UUID, 400

    box = get_box(request['uuid'])
    if box is None:
        return BAD_BOX_UUID, 404

    return jsonify({'available': not box.pkgs_up_to_date()})


@app.route('/box/pkg/versions', methods=['POST'])
def box_set_pkg_versions():
    if 'uuid' not in request:
        return BAD_BOX_UUID, 400

    if 'pkgs' not in request:
        return MISSING_PARAM, 400

    box = get_box(request['uuid'])
    if box is None:
        return BAD_BOX_UUID, 404

    # todo: validate and set pkg versions

    return jsonify({'done': True}), 200


def main():
    serve(app, host='127.0.0.1', port=API_PORT)
